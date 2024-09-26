rm(list=ls())

setwd("C:/Users/jshym/OneDrive/Documents/School/TU/Graduate/Research/Not All Explanatations Are Created Equal/social_security_explainer/instance")

library(RSQLite)
library(dplyr)
library(tidyr)
library(jsonlite)
library(ggplot2)
library(effectsize)

get_table_dfs <- function(db_filepath) {
  con <- dbConnect(drv=RSQLite::SQLite(), dbname=db_filepath)
  tables <- dbListTables(con)
  tables <- tables[tables != "sqlite_sequence"] # exclude sqlite_sequence (contains table information)
  t_dfs <- vector("list", length=length(tables))
  names(t_dfs) <- tables
  for (i in seq(along=tables)) {
    t_dfs[[i]] <- dbGetQuery(conn=con, statement=paste("SELECT * FROM '", tables[[i]], "'", sep=""))
  }
  dbDisconnect(con)
  return(t_dfs)
}

get_survey_dfs <- function(raw_surveys) {
  types <- unique(raw_surveys$type)
  s_dfs <- vector("list", length=length(types))
  names(s_dfs) <- types
  for (i in seq(along=types)) {
    old_survey_df <- raw_surveys[raw_surveys$type == types[[i]], ]
    new_survey_df <- old_survey_df %>% 
      rowwise() %>%
      do(data.frame(fromJSON(.$data, flatten = T))) %>%
      ungroup() %>% 
      bind_cols(old_survey_df %>% select(-c(data,type)))
    s_dfs[[i]] <- new_survey_df
  }
  return(s_dfs)
}

# start_date <- as.POSIXct("2024-03-08")
start_date <- as.POSIXct("2024-09-24")

#### Obtain and clean SQLite table data frames ####

table_dfs <- get_table_dfs("application 2.db")

users <- table_dfs$user %>% filter(start_time >= start_date, mturk_id %>% startsWith("6") | mturk_id %>% startsWith("5"))
users$experiment_completed <- users$experiment_completed %>% as.logical()
users$failed_attention_checks <- users$failed_attention_checks %>% as.logical()
users$start_time <- users$start_time %>% as.POSIXct()
users$end_time <- users$end_time %>% as.POSIXct()
users$consent <- users$consent %>% as.logical()
users$protocol <- users$protocol %>% ordered(levels=c("none", "placebic", "actionable"))
users$study_duration <- users$end_time - users$start_time
users$bonus_comp <- pmax(users$compensation - 2.7, 0)

explanations <- table_dfs$explanation
explanations$protocol <- explanations$protocol %>% ordered(levels=c("none", "placebic", "actionable"))

sections <- table_dfs$section %>% filter(start_time >= start_date, mturk_id %>% startsWith("6") | mturk_id %>% startsWith("5"))
sections$section <- sections$section %>% as.factor()
sections$protocol <- sections$protocol %>% ordered(levels=c("none", "placebic", "actionable"))
sections$start_time <- sections$start_time %>% as.POSIXct()
sections$end_time <- sections$end_time %>% as.POSIXct()
sections$duration <- sections$end_time - sections$start_time
sections$time_per_scenario <- sections$duration/sections$num_scenarios
sections$time_per_selection <- sections$duration/sections$num_selections
sections$error_per_section <- sections$error/sections$num_selections
sections$user.protocol <- (sections %>% left_join(users, join_by(mturk_id)))$protocol.y

selections <- table_dfs$selection %>% filter(timestamp >= start_date, mturk_id %>% startsWith("6") | mturk_id %>% startsWith("5"))
selections$timestamp <- selections$timestamp %>% as.POSIXct()
selections$user.protocol <- (selections %>% left_join(users, join_by(mturk_id)))$protocol
selections$section <- (selections %>% left_join(sections, join_by(section_id==id)))$section

scenarios <- table_dfs$scenario %>% filter(section %in% c("practice", "testing"))
scenarios$theme <- scenarios$theme %>% as.factor()
scenarios$marital_status <- scenarios$marital_status %>% as.factor()
scenarios$gender_a <- scenarios$gender_a %>% as.factor()
scenarios$gender_b <- scenarios$gender_b %>% as.factor()

surveys <- table_dfs$survey %>% filter(timestamp >= start_date, mturk_id %>% startsWith("6") | mturk_id %>% startsWith("5"))
surveys$timestamp <- surveys$timestamp %>% as.POSIXct()
surveys$user.protocol <- (surveys %>% left_join(users, join_by(mturk_id)))$protocol

#### Obtain and clean survey data frames ####

survey_dfs <- get_survey_dfs(surveys)

demographics <- survey_dfs$demographics
demographics$age <- demographics$age %>% as.ordered()
demographics$gender <- demographics$gender %>% as.factor()
demographics$ethnicity <- demographics$ethnicity %>% as.factor()
demographics$education <- demographics$education %>% ordered(
  levels=c("High school", "Some college, no degree", "Associate degree", "Bachelor's degree", "Master's/Graduate Degree"),
  labels=c("High school", "Some college", "Associate", "Bachelor", "Master+")
)
demographics$attention.check <- demographics$attention.check %>% as.integer()
demographics$soc.sec.skill <- demographics$soc.sec.skill %>% ordered(levels=c("Beginner", "Intermediate", "Expert"))

final_surveys <- survey_dfs$final_survey
final_surveys$sat.outcome.1 <- final_surveys$sat.outcome.1 %>% as.integer()
final_surveys$sat.outcome.2 <- final_surveys$sat.outcome.2 %>% as.integer()
final_surveys$sat.outcome.3 <- final_surveys$sat.outcome.3 %>% as.integer()
final_surveys$sat.agent.1 <- final_surveys$sat.agent.1 %>% as.integer()
final_surveys$sat.agent.2 <- final_surveys$sat.agent.2 %>% as.integer()
final_surveys$sat.agent.3 <- final_surveys$sat.agent.3 %>% as.integer()
final_surveys$exp.power.1 <- final_surveys$exp.power.1 %>% as.integer()
final_surveys$exp.power.2 <- final_surveys$exp.power.2 %>% as.integer()
final_surveys$exp.power.3 <- final_surveys$exp.power.3 %>% as.integer()
final_surveys$attention.check.1 <- final_surveys$attention.check.1 %>% as.integer()
final_surveys$attention.check.2 <- final_surveys$attention.check.2 %>% as.integer()

feedback <- survey_dfs$feedback
names(feedback)[1] <- "text"

#### Dropped Users ####

dropped_ids <- users %>% filter(experiment_completed == F) %>% select(mturk_id) %>% unlist()
users %>% filter(mturk_id %in% c(dropped_ids))
demographics %>% filter(mturk_id %in% dropped_ids)
sections %>% filter(mturk_id %in% dropped_ids, section == "practice")
sections %>% filter(mturk_id %in% dropped_ids, section == "testing")
final_surveys %>% filter(mturk_id %in% dropped_ids) %>% select(mturk_id)

#### Section Durations ####

users$study_duration %>% as.double() %>% median(na.rm = T)
(users %>% inner_join(demographics, join_by(mturk_id)) %>% mutate(login.demo.duration = timestamp - start_time) %>% select(login.demo.duration) %>% unlist()/60) %>% median(na.rm = T)
(sections %>% filter(section == "practice") %>% select(duration) %>% unlist()/60) %>% median(na.rm = T)
(sections %>% filter(section == "testing") %>% select(duration) %>% unlist()/60) %>% median(na.rm = T)
(sections %>% inner_join(final_surveys, join_by(mturk_id)) %>% mutate(final_survey.duration = timestamp - end_time) %>% select(final_survey.duration) %>% unlist()/60) %>% median(na.rm = T)

#### Protocol Counts ####

users %>% select(protocol) %>% table()
users %>% filter(experiment_completed) %>% select(protocol) %>% table()

#### Demographics ####

demographics %>% ggplot(aes(x = age)) +
  geom_bar(fill = "skyblue", color = "black") +
  labs(title = "Distribution of Age Groups", x = "Age group", y = "Count") +
  theme_minimal()

demographics %>% group_by(gender) %>% summarize(count = n()) %>% ggplot(aes(x = "", y = count, fill = gender)) +
  geom_bar(stat = "identity", width = 1, color = "white") +
  coord_polar("y", start = 0) +
  labs(title = "Distribution of Gender", x = "Gender", y = "Count") +
  theme_void() +
  theme(
    legend.title = element_blank(),
    legend.position = c(.18, .85),
    plot.title = element_text(vjust = -5, hjust = .5)
  )

demographics %>% group_by(ethnicity) %>% summarize(count = n()) %>% ggplot(aes(x = "", y = count, fill = ethnicity)) +
  geom_bar(stat = "identity", width = 1, color = "white") +
  coord_polar("y", start = 0) +
  labs(title = "Distribution of Ethnicity", x = "Enthicity", y = "Count") +
  theme_void() +
  theme(
    legend.title = element_blank(),
    legend.position = c(.18, .85),
    plot.title = element_text(vjust = -5, hjust = .5)
  )

demographics %>% ggplot(aes(x = education)) +
  geom_bar(fill = "skyblue", color = "black") +
  labs(title = "Distribution of Education Levels", x = "Education level", y = "Count") +
  theme_minimal()

demographics %>% ggplot(aes(x = soc.sec.skill)) +
  geom_bar(fill = "skyblue", color = "black") +
  labs(title = "Distribution of Social Security Skill", x = "Skill level", y = "Count") +
  theme_minimal()

sections %>% 
  filter(section == "testing", num_scenarios > 0) %>% 
  inner_join(demographics, join_by(mturk_id)) %>% 
  ggplot(aes(x = soc.sec.skill, y = error/num_selections)) +
  geom_boxplot() +
  ylab("error per selection")

#### Attention Checks ####

demographics$attention.check %>% hist(breaks = seq(0.5,5.5), main='Select "Agree"')
final_surveys$attention.check.1 %>% hist(breaks = seq(0.5,7.5), main='Select "Strongly Agree"')
final_surveys$attention.check.2 %>% hist(breaks = seq(0.5,7.5), main="Did You Just Solve Chess Puzzles?")

#### Bonus Compensation ####

users %>% 
  select(mturk_id, completion_code, bonus_comp) %>% 
  filter(bonus_comp > 0) %>%
  arrange(mturk_id)

#### Feedback ####

feedback %>% select(text, mturk_id) %>% print(n = 500)

#### Performance: Error Per Selection ####

# Data filtering
attempted_sections <- sections %>% filter(num_scenarios > 0) %>% mutate(error_per_selection = error/num_selections)
# Box plots
attempted_sections %>% ggplot(aes(x = user.protocol, y = error_per_selection, col = section)) + geom_boxplot()
# Tests
anova.error.all <- aov(error_per_selection ~ user.protocol, data = attempted_sections)
tukey.error.all <- TukeyHSD(anova.error.all)
anova.error.practice <- aov(error_per_selection ~ user.protocol, data = attempted_sections %>% filter(section == "practice"))
tukey.error.practice <- TukeyHSD(anova.error.practice)
anova.error.testing <- aov(error_per_selection ~ user.protocol, data = attempted_sections %>% filter(section == "testing"))
tukey.error.testing <- TukeyHSD(anova.error.testing)
# Stats
anova.error.all %>% summary()
tukey.error.all
tukey.error.all %>% plot()
title(main = "error per selection (all)", line = 1)
anova.error.practice %>% summary()
tukey.error.practice
tukey.error.practice %>% plot()
title(main = "error per selection (practice)", line = 1)
anova.error.testing %>% summary()
tukey.error.testing
tukey.error.testing %>% plot()
title(main = "error per selection (testing)", line = 1)

#### Performance: Bonus Compensation ####

# Data filtering
protocol_users <- users %>% filter(!is.na(protocol))
protocol_users %>% select(bonus_comp) %>% unlist() %>% hist()
protocol_users.bonus <- protocol_users %>% filter(bonus_comp > 0)
protocol_users.bonus %>% select(bonus_comp) %>% unlist() %>% hist()
nrow(protocol_users.bonus) / nrow(protocol_users)
# Box plots
protocol_users %>% ggplot(aes(x = protocol, y = bonus_comp)) + geom_boxplot()
protocol_users.bonus %>% ggplot(aes(x = protocol, y = bonus_comp)) + geom_boxplot()
# Tests
anova.bonus_comp.all <- aov(bonus_comp ~ protocol, data = protocol_users)
tukey.bonus_comp.all <- TukeyHSD(anova.bonus_comp.all)
anova.bonus_comp.few <- aov(bonus_comp ~ protocol, data = protocol_users.bonus)
tukey.bonus_comp.few <- TukeyHSD(anova.bonus_comp.few)
# Stats
anova.bonus_comp.all %>% summary()
tukey.bonus_comp.all
tukey.bonus_comp.all %>% plot()
title(main = "bonus compensation (all)", line = 1)
anova.bonus_comp.few %>% summary()
tukey.bonus_comp.few
tukey.bonus_comp.few %>% plot()
title(main = "bonus compensation (few)", line = 1)

#### Performance: Time Per Selection ####

# Data filtering
possible_sections <- sections %>% filter(time_per_selection <= 600/18)
possible_sections %>% select(time_per_selection) %>% unlist() %>% hist()
# Box plots
possible_sections %>% ggplot(aes(x = user.protocol, y = time_per_selection, col = section)) + geom_boxplot()
# Tests
anova.time_per_selection.all <- aov(time_per_selection %>% as.double() ~ user.protocol, data = possible_sections)
tukey.time_per_selection.all <- TukeyHSD(anova.time_per_selection.all)
anova.time_per_selection.practice <- aov(time_per_selection %>% as.double() ~ user.protocol, data = possible_sections %>% filter(section == "practice"))
tukey.time_per_selection.practice <- TukeyHSD(anova.time_per_selection.practice)
anova.time_per_selection.testing <- aov(time_per_selection %>% as.double() ~ user.protocol, data = possible_sections %>% filter(section == "testing"))
tukey.time_per_selection.testing <- TukeyHSD(anova.time_per_selection.testing)
# Stats
anova.time_per_selection.all %>% summary()
tukey.time_per_selection.all
tukey.time_per_selection.all %>% plot()
title(main = "time per selection (all)", line = 1)
anova.time_per_selection.practice %>% summary()
tukey.time_per_selection.practice
tukey.time_per_selection.practice %>% plot()
title(main = "time per selection (practice)", line = 1)
anova.time_per_selection.testing %>% summary()
tukey.time_per_selection.testing
tukey.time_per_selection.testing %>% plot()
title(main = "time per selection (testing)", line = 1)

#### Performance: Learning by Theme ####

scenarios %>% 
  inner_join(selections, join_by(id == scenario_id, section)) %>% 
  group_by(theme, section) %>% 
  summarize(
    count = n(),
    error_a = sum(error_a, na.rm = T),
    error_b = sum(error_b, na.rm = T),
    error_per_selection = (error_a + error_b)/count/(1+as.integer(error_b!=0))
  ) %>% 
  ggplot(aes(x=section, y=error_per_selection, group=theme, col=theme, label=theme)) +
  geom_line() +
  geom_label()

#### Performance: Learning by Protocol ####

scenarios %>% 
  inner_join(selections, join_by(id == scenario_id, section)) %>% 
  group_by(user.protocol, section) %>% 
  summarize(
    count = n(),
    error_a = sum(error_a, na.rm = T),
    error_b = sum(error_b, na.rm = T),
    error_per_selection = (error_a + error_b)/count/(1+as.integer(error_b!=0))
  ) %>% 
  ggplot(aes(x=section, y=error_per_selection, group=user.protocol, col=user.protocol, label=user.protocol)) +
  geom_line() +
  geom_label()

scenario_errors <- scenarios %>% 
  inner_join(selections, join_by(id == scenario_id, section)) %>% 
  group_by(section, id, order, user.protocol) %>% 
  summarize(
    count = n(),
    error_a = sum(error_a, na.rm = T),
    error_b = sum(error_b, na.rm = T),
    error_per_selection = (error_a + error_b)/count/(1+as.integer(error_b!=0))
  ) %>% 
  arrange(section, order, user.protocol)
scenario_errors$order[31:60] <- scenario_errors$order[31:60] + 10
scenario_errors %>% 
  ggplot(aes(x = order, y = error_per_selection, col = user.protocol)) +
  geom_point() +
  geom_smooth(method = "lm", formula = y ~ poly(x, 3), se = F) +
  scale_x_continuous(breaks = 1:20) +
  scale_color_manual(values = c("none" = "#0072B2", "placebic" = "#D55E00", "actionable" = "#009E73")) +
  geom_vline(xintercept = 10.5, linetype = "dotted") +
  annotate("text", x = 5.5, y = .082, label = "Practice", size = 5) +
  annotate("text", x = 15.5, y = .082, label = "Testing", size = 5) +
  labs(
    title = "Scenario Error Progression by Section",
    x = "Puzzle number",
    y = "Error per selection",
    color = "User protocol"
  ) +
  theme(
    panel.grid.minor.x = element_blank(),
    legend.position = c(.14, .86)
  )

#### Final Surveys ####

# Data wrangling
final_surveys.averaged <- final_surveys %>% 
  mutate(
    sat.practice = rowSums(select(., starts_with("sat.outcome")))/3,
    sat.agent = rowSums(select(., starts_with("sat.agent")))/3,
    exp.power = rowSums(select(., starts_with("exp.power")))/3
  ) %>% 
  inner_join(users, join_by(mturk_id))
# Box plots
final_surveys.averaged %>% ggplot(aes(x = protocol, y = sat.practice)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Satisfaction with Practice by Protocol")
final_surveys.averaged %>% filter(protocol != "none") %>% ggplot(aes(x = protocol, y = sat.agent)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Satisfaction with Agent by Protocol")
final_surveys.averaged %>% filter(protocol != "none") %>% ggplot(aes(x = protocol, y = exp.power)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Explanatory Power by Protocol")
# Tests
anova.sat.practice <- aov(sat.practice ~ protocol, data = final_surveys.averaged)
tukey.sat.practice <- TukeyHSD(anova.sat.practice)

anova.sat.agent <- aov(sat.agent ~ protocol, data = final_surveys.averaged %>% filter(protocol != "none"))
tukey.sat.agent <- TukeyHSD(anova.sat.agent)

anova.exp.power <- aov(exp.power ~ protocol, data = final_surveys.averaged %>% filter(protocol != "none"))
tukey.exp.power <- TukeyHSD(anova.exp.power)
# Stats
anova.sat.practice %>% summary()
tukey.sat.practice
tukey.sat.practice %>% plot()
title(main = "Satisfaction with practice section", line = 1)

anova.sat.agent %>% summary()
tukey.sat.agent
tukey.sat.agent %>% plot()
title(main = "Satisfaction with agent", line = 1)

anova.exp.power %>% summary()
tukey.exp.power
tukey.exp.power %>% plot()
title(main = "Explanatory power", line = 1)
