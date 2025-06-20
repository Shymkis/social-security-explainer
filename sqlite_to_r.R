rm(list=ls())

# setwd to the instance folder

library(RSQLite)
library(dplyr)
library(tidyr)
library(jsonlite)
library(ggplot2)
library(effectsize)
library(TOSTER)

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
demographics$ethnicity <- demographics$ethnicity %>% factor(
  levels=c("Native or American Indian", "Hispanic/Latino", "Asian or Pacific Islander", "White", "Black or African American", "Other"),
  labels=c("Native American", "Hispanic/Latino", "AAPI", "White", "Black", "Other")
)
demographics$education <- demographics$education %>% ordered(
  levels=c("Less than high school", "High school", "Some college, no degree", "Associate degree", "Bachelor's degree", "Master's/Graduate Degree", "PhD or similar"),
  labels=c("< High school", "High school", "Some college", "Associate", "Bachelor", "Master", "PhD")
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
  labs(
    # title = "Distribution of Age Groups",
    x = "Age group", y = "Count") +
  theme_minimal()

demographics.completed %>% group_by(gender) %>% summarize(count = n()) %>% 
  ggplot(aes(x = "", y = count, fill = gender)) +
  geom_bar(stat = "identity", color = "black") +
  coord_polar("y") +
  labs(
    # title = "Distribution of Gender",
    x = "Gender", y = "Count") +
  theme_void() +
  theme(
    plot.margin = margin(t=-10,b=-10,r=-10),
    legend.title = element_blank(),
    legend.position = "left",
    legend.margin = margin(r=-10)
    # plot.title = element_text(vjust = -5, hjust = .5)
  )

demographics.completed %>% 
  group_by(ethnicity) %>% summarize(count = n()) %>% ggplot(aes(x = "", y = count, fill = ethnicity)) +
  geom_bar(stat = "identity", width = 1, color = "black") +
  coord_polar("y", start = 0) +
  labs(
    # title = "Distribution of Ethnicity",
    x = "Enthicity", y = "Count") +
  theme_void() +
  theme(
    plot.margin = margin(t=-10,b=-10,r=-10),
    legend.title = element_blank(),
    legend.position = "left",
    legend.margin = margin(r=-10)
    # plot.title = element_text(vjust = -5, hjust = .5)
  )

demographics.completed %>% ggplot(aes(x = education)) +
  geom_bar(fill = "skyblue", color = "black") +
  labs(
    # title = "Distribution of Education Levels",
    x = "Education level", y = "Count") +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  theme_minimal()

demographics.completed %>% ggplot(aes(x = soc.sec.skill)) +
  geom_bar(fill = "skyblue", color = "black") +
  labs(
    # title = "Distribution of Domain Knowledge",
    x = "Domain expertise", y = "Count") +
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

#### Performance: Error ####

# Box plots
sections.completed %>% 
  ggplot(aes(x = user.protocol, y = error_per_selection, fill = section)) +
  geom_boxplot() +
  labs(x = "Protocol", y = "Error per selection") +
  theme(
    legend.background = element_blank(),
    legend.direction = "horizontal",
    legend.key = element_blank(),
    legend.position = c(.5, .94),
    legend.title = element_blank()
  )
# Tests
anova.avg_error.all <- aov(error_per_selection ~ user.protocol, data = sections.completed)
tukey.avg_error.all <- TukeyHSD(anova.avg_error.all)
anova.avg_error.practice <- aov(error_per_selection ~ user.protocol, data = sections.completed %>% filter(section == "practice"))
tukey.avg_error.practice <- TukeyHSD(anova.avg_error.practice)
anova.avg_error.testing <- aov(error_per_selection ~ user.protocol, data = sections.completed %>% filter(section == "testing"))
tukey.avg_error.testing <- TukeyHSD(anova.avg_error.testing)
# Stats
anova.avg_error.all %>% summary()
effectsize(anova.avg_error.all, verbose = F)
tukey.avg_error.all
tukey.avg_error.all %>% plot()
title(main = "Error per selection (all)", line = 1)

anova.avg_error.practice %>% summary()
effectsize(anova.avg_error.practice, verbose = F)
tukey.avg_error.practice
tukey.avg_error.practice %>% plot()
title(main = "Error per selection (practice)", line = 1)

anova.avg_error.testing %>% summary()
effectsize(anova.avg_error.testing, verbose = F)
tukey.avg_error.testing
tukey.avg_error.testing %>% plot()
title(main = "Error per selection (testing)", line = 1)

# TOST
tost.avg_error.all.NP <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "actionable"), eqb = .5)
tost.avg_error.all.NA <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "placebic"), eqb = .5)
tost.avg_error.all.PA <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "none"), eqb = .5)

tost.avg_error.practice.NP <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "actionable", section == "practice"), eqb = .5)
tost.avg_error.practice.NA <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "placebic", section == "practice"), eqb = .5)
tost.avg_error.practice.PA <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "none", section == "practice"), eqb = .5)

tost.avg_error.testing.NP <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "actionable", section == "testing"), eqb = .5)
tost.avg_error.testing.NA <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "placebic", section == "testing"), eqb = .5)
tost.avg_error.testing.PA <- t_TOST(error_per_selection ~ user.protocol, data = sections.completed %>% filter(user.protocol != "none", section == "testing"), eqb = .5)

tost.avg_error.all.NP
tost.avg_error.all.NP %>% plot()
tost.avg_error.all.NA
tost.avg_error.all.NA %>% plot()
tost.avg_error.all.PA
tost.avg_error.all.PA %>% plot()

tost.avg_error.practice.NP
tost.avg_error.practice.NP %>% plot()
tost.avg_error.practice.NA
tost.avg_error.practice.NA %>% plot()
tost.avg_error.practice.PA
tost.avg_error.practice.PA %>% plot()

tost.avg_error.testing.NP
tost.avg_error.testing.NP %>% plot()
tost.avg_error.testing.NA
tost.avg_error.testing.NA %>% plot()
tost.avg_error.testing.PA
tost.avg_error.testing.PA %>% plot()

#### Performance: Bonus Compensation ####

# Box plots
users.completed %>% rename(user.protocol = protocol) %>% 
  ggplot(aes(x = user.protocol, y = bonus_comp)) +
  geom_boxplot() +
  labs(x = "Protocol", y = "Bonus Compensation")
# Tests
anova.bonus_comp <- aov(bonus_comp ~ user.protocol, data = users.completed %>% rename(user.protocol = protocol))
tukey.bonus_comp <- TukeyHSD(anova.bonus_comp)
# Stats
anova.bonus_comp %>% summary()
effectsize(anova.bonus_comp, verbose = F)
tukey.bonus_comp
tukey.bonus_comp %>% plot()
title(main = "Bonus compensation", line = 1)

# TOST
tost.bonus_comp.NP <- t_TOST(bonus_comp ~ user.protocol, data = users.completed %>% rename(user.protocol = protocol) %>% filter(user.protocol != "actionable"), eqb = .1)
tost.bonus_comp.NA <- t_TOST(bonus_comp ~ user.protocol, data = users.completed %>% rename(user.protocol = protocol) %>% filter(user.protocol != "placebic"), eqb = .1)
tost.bonus_comp.PA <- t_TOST(bonus_comp ~ user.protocol, data = users.completed %>% rename(user.protocol = protocol) %>% filter(user.protocol != "none"), eqb = .1)

tost.bonus_comp.NP
tost.bonus_comp.NP %>% plot()
tost.bonus_comp.NA
tost.bonus_comp.NA %>% plot()
tost.bonus_comp.PA
tost.bonus_comp.PA %>% plot()

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
    color = "Protocol"
  ) +
  theme(
    panel.grid.minor.x = element_blank(),
    legend.position = c(.14, .86)
  )

#### Final Surveys ####

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
  labs(x = "Protocol", y = "Satisfaction with practice")
final_surveys.averaged %>% filter(user.protocol != "none") %>% ggplot(aes(x = user.protocol, y = sat.agent)) +
  geom_boxplot() +
  ylim(1,7) + 
  labs(x = "Protocol", y = "Satisfaction with agent")
final_surveys.averaged %>% filter(user.protocol != "none") %>% ggplot(aes(x = user.protocol, y = exp.power)) +
  geom_boxplot() +
  ylim(1,7) +
  labs(x = "Protocol", y = "Explanatory power")
# Tests
anova.sat.practice.avg <- aov(sat.practice ~ user.protocol, data = final_surveys.averaged)
tukey.sat.practice.avg <- TukeyHSD(anova.sat.practice.avg)
anova.sat.agent.avg <- aov(sat.agent ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "none"))
tukey.sat.agent.avg <- TukeyHSD(anova.sat.agent.avg)
anova.exp.power.avg <- aov(exp.power ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "none"))
tukey.exp.power.avg <- TukeyHSD(anova.exp.power.avg)
# Stats
anova.sat.practice.avg %>% summary()
effectsize(anova.sat.practice.avg, verbose = F)
tukey.sat.practice.avg
tukey.sat.practice.avg %>% plot()
title(main = "Satisfaction with practice section", line = 1)

anova.sat.agent.avg %>% summary()
effectsize(anova.sat.agent.avg, verbose = F)
tukey.sat.agent.avg
tukey.sat.agent.avg %>% plot()
title(main = "Satisfaction with agent", line = 1)

anova.exp.power.avg %>% summary()
effectsize(anova.exp.power.avg, verbose = F)
tukey.exp.power.avg
tukey.exp.power.avg %>% plot()
title(main = "Explanatory power", line = 1)

# TOST
tost.sat_practice.avg.NP <- t_TOST(sat.practice ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "actionable"), eqb = .5)
tost.sat_practice.avg.NA <- t_TOST(sat.practice ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "placebic"), eqb = .5)
tost.sat_practice.avg.PA <- t_TOST(sat.practice ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "none"), eqb = .5)
tost.sat_agent.avg <- t_TOST(sat.agent ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "none"), eqb = .5)
tost.exp_power.avg <- t_TOST(exp.power ~ user.protocol, data = final_surveys.averaged %>% filter(user.protocol != "none"), eqb = .5)

tost.sat_practice.avg.NP
tost.sat_practice.avg.NP %>% plot()
tost.sat_practice.avg.NA
tost.sat_practice.avg.NA %>% plot()
tost.sat_practice.avg.PA
tost.sat_practice.avg.PA %>% plot()
tost.sat_agent.avg
tost.sat_agent.avg %>% plot()
tost.exp_power.avg
tost.exp_power.avg %>% plot()

#### Correlating Survey with Performance: Error ####

final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id)) %>% filter(section == "testing") %>% 
  ggplot(aes(x = error_per_selection, y = sat.practice)) +
  geom_point() + geom_smooth(method = lm) +
  labs(x = "Error per selection", y = "Satisfaction with practice")
cor.test(
  (final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id)) %>% filter(section == "testing"))$sat.practice,
  (final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id)) %>% filter(section == "testing"))$error_per_selection,
  method = "pearson"
)

final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id, user.protocol)) %>% filter(section == "testing", user.protocol != "none") %>% 
  ggplot(aes(x = error_per_selection, y = sat.agent)) +
  geom_jitter(height=.1) + geom_smooth(method = lm) +
  labs(x = "Error per selection", y = "Satisfaction with agent")
cor.test(
  (final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id, user.protocol)) %>% filter(section == "testing", user.protocol != "none"))$sat.agent,
  (final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id, user.protocol)) %>% filter(section == "testing", user.protocol != "none"))$error_per_selection,
  method = "pearson"
)

final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id, user.protocol)) %>% filter(section == "testing", user.protocol != "none") %>% 
  ggplot(aes(x = error_per_selection, y = exp.power)) +
  geom_point() + geom_smooth(method = lm) +
  labs(x = "Error per selection", y = "Explanatory power")
cor.test(
  (final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id, user.protocol)) %>% filter(section == "testing", user.protocol != "none"))$exp.power,
  (final_surveys.averaged %>% inner_join(sections.completed, join_by(mturk_id, user.protocol)) %>% filter(section == "testing", user.protocol != "none"))$error_per_selection,
  method = "pearson"
)

#### Correlating Survey with Performance: Bonus ####

final_surveys.averaged %>% inner_join(users.completed) %>% 
  ggplot(aes(x = bonus_comp, y = sat.practice)) +
  geom_jitter(height=.1) + geom_smooth(method = lm) +
  labs(x = "Bonus compensation", y = "Satisfaction with practice section")
cor.test(
  (final_surveys.averaged %>% inner_join(users.completed))$sat.practice,
  (final_surveys.averaged %>% inner_join(users.completed))$bonus_comp,
  method = "pearson"
)

final_surveys.averaged %>% inner_join(users.completed) %>% filter(user.protocol != "none") %>% 
  ggplot(aes(x = bonus_comp, y = sat.agent)) +
  geom_jitter(height=.1) + geom_smooth(method = lm) +
  labs(x = "Bonus compensation", y = "Satisfaction with agent")
cor.test(
  (final_surveys.averaged %>% inner_join(users.completed) %>% filter(user.protocol != "none"))$sat.agent,
  (final_surveys.averaged %>% inner_join(users.completed) %>% filter(user.protocol != "none"))$bonus_comp,
  method = "pearson"
)

final_surveys.averaged %>% inner_join(users.completed) %>% filter(user.protocol != "none") %>% 
  ggplot(aes(x = bonus_comp, y = exp.power)) +
  geom_jitter(height=.1) + geom_smooth(method = lm) +
  labs(x = "Bonus compensation", y = "Explanatory power")
cor.test(
  (final_surveys.averaged %>% inner_join(users.completed) %>% filter(user.protocol != "none"))$exp.power,
  (final_surveys.averaged %>% inner_join(users.completed) %>% filter(user.protocol != "none"))$bonus_comp,
  method = "pearson"
)
