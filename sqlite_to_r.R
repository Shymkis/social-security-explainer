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

start_date <- as.POSIXct("2024-09-26")

#### Obtain and clean SQLite table data frames ####

table_dfs <- get_table_dfs("application.db")

users <- table_dfs$user %>% filter(start_time >= start_date, mturk_id %>% startsWith("6") | mturk_id %>% startsWith("5"))
users$experiment_completed <- users$experiment_completed %>% as.logical()
users$failed_attention_checks <- users$failed_attention_checks %>% as.logical()
users$start_time <- users$start_time %>% as.POSIXct()
users$end_time <- users$end_time %>% as.POSIXct()
users$consent <- users$consent %>% as.logical()
users$protocol <- users$protocol %>% ordered(levels=c("none", "placebic", "actionable"))
users$study_duration <- users$end_time - users$start_time
users$bonus_comp <- pmax(users$compensation - 2, 0)

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
sections$error_per_selection <- sections$error/sections$num_selections
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

completed_ids <- users %>% filter(experiment_completed == T) %>% select(mturk_id) %>% unlist()
users %>% filter(!(mturk_id %in% completed_ids))
demographics %>% filter(!(mturk_id %in% completed_ids))
sections %>% filter(!(mturk_id %in% completed_ids), section == "practice")
sections %>% filter(!(mturk_id %in% completed_ids), section == "testing")
final_surveys %>% filter(!(mturk_id %in% completed_ids)) %>% select(mturk_id)

#### Keep Completed Data ####

users.completed <- users %>% filter(mturk_id %in% completed_ids)
demographics.completed <- demographics %>% filter(mturk_id %in% completed_ids)
selections.completed <- selections %>% filter(mturk_id %in% completed_ids)
sections.completed <- sections %>% filter(mturk_id %in% completed_ids)
final_surveys.completed <- final_surveys %>% filter(mturk_id %in% completed_ids)

#### Section Durations ####

users.completed$study_duration %>% as.double() %>% median(na.rm = T)
(users.completed %>% inner_join(demographics.completed, join_by(mturk_id)) %>% mutate(login.demo.duration = timestamp - start_time) %>% select(login.demo.duration) %>% unlist()/60) %>% median(na.rm = T)
(sections.completed %>% filter(section == "practice") %>% select(duration) %>% unlist()/60) %>% median(na.rm = T)
(sections.completed %>% filter(section == "testing") %>% select(duration) %>% unlist()/60) %>% median(na.rm = T)
(sections.completed %>% inner_join(final_surveys.completed, join_by(mturk_id)) %>% mutate(final_survey.duration = timestamp - end_time) %>% select(final_survey.duration) %>% unlist()/60) %>% median(na.rm = T)

#### Protocol Counts ####

users.completed %>% select(protocol) %>% table()

#### Demographics ####

demographics.completed %>% 
  ggplot(aes(x = age)) +
  geom_bar(fill = "skyblue", color = "black") +
  labs(title = "Distribution of Age Groups", x = "Age group", y = "Count") +
  theme_minimal()

demographics.completed %>% group_by(gender) %>% summarize(count = n()) %>% 
  ggplot(aes(x = "", y = count, fill = gender)) +
  geom_bar(stat = "identity", width = 1, color = "white") +
  coord_polar("y", start = 0) +
  labs(title = "Distribution of Gender", x = "Gender", y = "Count") +
  theme_void() +
  theme(
    legend.title = element_blank(),
    legend.position = c(.18, .85),
    plot.title = element_text(vjust = -5, hjust = .5)
  )

demographics.completed %>% 
  group_by(ethnicity) %>% summarize(count = n()) %>% ggplot(aes(x = "", y = count, fill = ethnicity)) +
  geom_bar(stat = "identity", width = 1, color = "white") +
  coord_polar("y", start = 0) +
  labs(title = "Distribution of Ethnicity", x = "Enthicity", y = "Count") +
  theme_void() +
  theme(
    legend.title = element_blank(),
    legend.position = c(.18, .85),
    plot.title = element_text(vjust = -5, hjust = .5)
  )

demographics.completed %>% ggplot(aes(x = education)) +
  geom_bar(fill = "skyblue", color = "black") +
  labs(title = "Distribution of Education Levels", x = "Education level", y = "Count") +
  theme_minimal()

demographics.completed %>% ggplot(aes(x = soc.sec.skill)) +
  geom_bar(fill = "skyblue", color = "black") +
  labs(title = "Distribution of Social Security Skill", x = "Skill level", y = "Count") +
  theme_minimal()

sections.completed %>% 
  filter(section == "testing", num_scenarios > 0) %>% 
  inner_join(demographics, join_by(mturk_id)) %>% 
  ggplot(aes(x = soc.sec.skill, y = error_per_selection)) +
  geom_boxplot()

#### Attention Checks ####
demographics %>% 
  ggplot(aes(x = attention.check)) +
  geom_bar(fill = "skyblue", color = "black") +
  xlim(c(0.5,5.5)) +
  labs(title = 'Select "Agree"', x = "Choices", y = "Count") +
  theme_minimal()

final_surveys %>% 
  ggplot(aes(x = attention.check.1)) +
  geom_bar(fill = "skyblue", color = "black") +
  xlim(c(0.5,7.5)) +
  labs(title = 'Select "Strongly Agree"', x = "Choices", y = "Count") +
  theme_minimal()

final_surveys %>% 
  ggplot(aes(x = attention.check.2)) +
  geom_bar(fill = "skyblue", color = "black") +
  xlim(c(0.5,7.5)) +
  labs(title = "Did You Just Solve Chess Puzzles?", x = "Choices", y = "Count") +
  theme_minimal()

#### Bonus Compensation ####

users.completed %>% select(mturk_id, bonus_comp) %>% arrange(mturk_id)

#### Feedback ####

feedback %>% select(text) %>% print(n = 500)

#### Performance: Total Error ####

# Box plots
sections.completed %>% ggplot(aes(x = user.protocol, y = error, col = section)) + geom_boxplot()
# Tests
anova.error.all <- aov(error ~ user.protocol, data = sections.completed)
tukey.error.all <- TukeyHSD(anova.error.all)
anova.error.practice <- aov(error ~ user.protocol, data = sections.completed %>% filter(section == "practice"))
tukey.error.practice <- TukeyHSD(anova.error.practice)
anova.error.testing <- aov(error ~ user.protocol, data = sections.completed %>% filter(section == "testing"))
tukey.error.testing <- TukeyHSD(anova.error.testing)
# Stats
effectsize(anova.error.all, verbose = F)
anova.error.all %>% summary()
tukey.error.all
tukey.error.all %>% plot()
title(main = "total error (all)", line = 1)

effectsize(anova.error.practice, verbose = F)
anova.error.practice %>% summary()
tukey.error.practice
tukey.error.practice %>% plot()
title(main = "total error (practice)", line = 1)

effectsize(anova.error.testing, verbose = F)
anova.error.testing %>% summary()
tukey.error.testing
tukey.error.testing %>% plot()
title(main = "total error (testing)", line = 1)

#### Performance: Error Per Selection ####

# Box plots
sections.completed %>% ggplot(aes(x = user.protocol, y = error_per_selection, col = section)) + geom_boxplot()
# Tests
anova.avg_error.all <- aov(error_per_selection ~ user.protocol, data = sections.completed)
tukey.avg_error.all <- TukeyHSD(anova.avg_error.all)
anova.avg_error.practice <- aov(error_per_selection ~ user.protocol, data = sections.completed %>% filter(section == "practice"))
tukey.avg_error.practice <- TukeyHSD(anova.avg_error.practice)
anova.avg_error.testing <- aov(error_per_selection ~ user.protocol, data = sections.completed %>% filter(section == "testing"))
tukey.avg_error.testing <- TukeyHSD(anova.avg_error.testing)
# Stats
effectsize(anova.avg_error.all, verbose = F)
anova.avg_error.all %>% summary()
tukey.avg_error.all
tukey.avg_error.all %>% plot()
title(main = "error per selection (all)", line = 1)

effectsize(anova.avg_error.practice, verbose = F)
anova.avg_error.practice %>% summary()
tukey.avg_error.practice
tukey.avg_error.practice %>% plot()
title(main = "error per selection (practice)", line = 1)

effectsize(anova.avg_error.testing, verbose = F)
anova.avg_error.testing %>% summary()
tukey.avg_error.testing
tukey.avg_error.testing %>% plot()
title(main = "error per selection (testing)", line = 1)

#### Performance: Bonus Compensation ####

# Box plots
users.completed %>% ggplot(aes(x = protocol, y = bonus_comp)) + geom_boxplot()
# Tests
anova.bonus_comp <- aov(bonus_comp ~ protocol, data = users.completed)
tukey.bonus_comp <- TukeyHSD(anova.bonus_comp)
# Stats
effectsize(anova.bonus_comp, verbose = F)
anova.bonus_comp %>% summary()
tukey.bonus_comp
tukey.bonus_comp %>% plot()
title(main = "bonus compensation", line = 1)

#### Performance: Learning by Theme ####

section_errors.theme <- scenarios %>% 
  inner_join(selections.completed, join_by(id == scenario_id, section)) %>% 
  group_by(theme, section) %>% 
  summarize(
    count = n(),
    error_a = sum(error_a, na.rm = T),
    error_b = sum(error_b, na.rm = T),
    error_per_selection = (error_a + error_b)/count/(1+as.integer(error_b!=0))
  )
section_errors.theme %>% 
  select(theme, section, error_per_selection) %>% 
  pivot_wider(names_from = section, values_from = error_per_selection) %>% 
  mutate(diff = testing - practice, pct_diff = diff/practice*100)
section_errors.theme %>% 
  ggplot(aes(x=section, y=error_per_selection, group=theme, col=theme, label=theme)) +
  geom_line() +
  geom_label()

#### Performance: Learning by Protocol ####

section_errors.protocol <- scenarios %>% 
  inner_join(selections.completed, join_by(id == scenario_id, section)) %>% 
  group_by(user.protocol, section) %>% 
  summarize(
    count = n(),
    error_a = sum(error_a, na.rm = T),
    error_b = sum(error_b, na.rm = T),
    error_per_selection = (error_a + error_b)/count/(1+as.integer(error_b!=0))
  )
section_errors.protocol %>% 
  select(user.protocol, section, error_per_selection) %>% 
  pivot_wider(names_from = section, values_from = error_per_selection) %>% 
  mutate(diff = testing - practice, pct_diff = diff/practice*100)
section_errors.protocol %>% 
  ggplot(aes(x=section, y=error_per_selection, group=user.protocol, col=user.protocol, label=user.protocol)) +
  geom_line() +
  geom_label()

scenario_errors <- scenarios %>% 
  inner_join(selections.completed, join_by(id == scenario_id, section)) %>% 
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
    x = "Scenario number",
    y = "Error per selection",
    color = "User protocol"
  ) +
  theme(
    panel.grid.minor.x = element_blank(),
    legend.position = c(.14, .86)
  )

#### Final Surveys: Total ####

# Data wrangling
final_surveys.sat_outcome <- final_surveys.completed %>% 
  select(user.protocol, sat.outcome.1, sat.outcome.2, sat.outcome.3) %>% 
  pivot_longer(starts_with("sat.outcome"), names_to = NULL, values_to = "sat.outcome")
final_surveys.sat_agent <- final_surveys.completed %>% 
  select(user.protocol, sat.agent.1, sat.agent.2, sat.agent.3) %>% 
  pivot_longer(starts_with("sat.agent"), names_to = NULL, values_to = "sat.agent")
final_surveys.exp_power <- final_surveys.completed %>% 
  select(user.protocol, exp.power.1, exp.power.2, exp.power.3) %>% 
  pivot_longer(starts_with("exp.power"), names_to = NULL, values_to = "exp.power")
# Box plots
final_surveys.sat_outcome %>% ggplot(aes(x = user.protocol, y = sat.outcome)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Satisfaction with Practice by Protocol")
final_surveys.sat_agent %>% filter(user.protocol != "none") %>% ggplot(aes(x = user.protocol, y = sat.agent)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Satisfaction with Agent by Protocol")
final_surveys.exp_power %>% filter(user.protocol != "none") %>% ggplot(aes(x = user.protocol, y = exp.power)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Explanatory Power by Protocol")
# Tests
anova.sat.practice.total <- aov(sat.outcome ~ user.protocol, data = final_surveys.sat_outcome)
tukey.sat.practice.total <- TukeyHSD(anova.sat.practice.total)
anova.sat.agent.total <- aov(sat.agent ~ user.protocol, data = final_surveys.sat_agent %>% filter(user.protocol != "none"))
tukey.sat.agent.total <- TukeyHSD(anova.sat.agent.total)
anova.exp.power.total <- aov(exp.power ~ user.protocol, data = final_surveys.exp_power %>% filter(user.protocol != "none"))
tukey.exp.power.total <- TukeyHSD(anova.exp.power.total)
# Stats
effectsize(anova.sat.practice.total, verbose = F)
anova.sat.practice.total %>% summary()
tukey.sat.practice.total
tukey.sat.practice.total %>% plot()
title(main = "Satisfaction with practice section", line = 1)

effectsize(anova.sat.agent.total, verbose = F)
anova.sat.agent.total %>% summary()
tukey.sat.agent.total
tukey.sat.agent.total %>% plot()
title(main = "Satisfaction with agent", line = 1)

effectsize(anova.exp.power.total, verbose = F)
anova.exp.power.total %>% summary()
tukey.exp.power.total
tukey.exp.power.total %>% plot()
title(main = "Explanatory power", line = 1)

#### Final Surveys: Averaged ####

# Data wrangling
final_surveys.averaged <- final_surveys.completed %>% 
  mutate(
    sat.practice = rowSums(select(., starts_with("sat.outcome")))/3,
    sat.agent = rowSums(select(., starts_with("sat.agent")))/3,
    exp.power = rowSums(select(., starts_with("exp.power")))/3
  )
# Box plots
final_surveys.averaged %>% ggplot(aes(x = user.protocol, y = sat.practice)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Satisfaction with Practice by Protocol")
final_surveys.averaged %>% filter(user.protocol != "none") %>% ggplot(aes(x = user.protocol, y = sat.agent)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Satisfaction with Agent by Protocol")
final_surveys.averaged %>% filter(user.protocol != "none") %>% ggplot(aes(x = user.protocol, y = exp.power)) +
  geom_boxplot() + 
  ylim(1,7) + 
  ggtitle("Explanatory Power by Protocol")
# Tests
anova.sat.practice.avg <- aov(sat.practice ~ user.protocol, data = final_surveys.averaged)
tukey.sat.practice.avg <- TukeyHSD(anova.sat.practice.avg)
anova.sat.agent.avg <- aov(sat.agent ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "none"))
tukey.sat.agent.avg <- TukeyHSD(anova.sat.agent.avg)
anova.exp.power.avg <- aov(exp.power ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "none"))
tukey.exp.power.avg <- TukeyHSD(anova.exp.power.avg)
# Stats
effectsize(anova.sat.practice.avg, verbose = F)
anova.sat.practice.avg %>% summary()
tukey.sat.practice.avg
tukey.sat.practice.avg %>% plot()
title(main = "Satisfaction with practice section", line = 1)

effectsize(anova.sat.agent.avg, verbose = F)
anova.sat.agent.avg %>% summary()
tukey.sat.agent.avg
tukey.sat.agent.avg %>% plot()
title(main = "Satisfaction with agent", line = 1)

effectsize(anova.exp.power.avg, verbose = F)
anova.exp.power.avg %>% summary()
tukey.exp.power.avg
tukey.exp.power.avg %>% plot()
title(main = "Explanatory power", line = 1)
