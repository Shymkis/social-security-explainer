rm(list=ls())

setwd("C:/Users/jshym/OneDrive/Documents/School/TU/Graduate/Research/Not All Explanatations Are Created Equal/chess_puzzle_explainer/instance")

library(RSQLite)
library(dplyr)
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

start_date <- as.POSIXct("2023-09-25")
restart_date <- as.POSIXct("2023-10-01")
rerestart_date <- as.POSIXct("2023-10-05")

#### Obtain and clean SQLite table data frames ####

table_dfs <- get_table_dfs("application.db")

explanations <- table_dfs$explanation
explanations$protocol <- explanations$protocol %>% ordered(levels=c("none", "placebic", "actionable"))

moves <- table_dfs$move %>% filter(start_time >= restart_date, mturk_id %>% startsWith("A"))
moves$start_time <- moves$start_time %>% as.POSIXct()
moves$end_time <- moves$end_time %>% as.POSIXct()
moves$mistake <- moves$mistake %>% as.logical()

puzzles <- table_dfs$puzzle
puzzles$theme <- puzzles$theme %>% as.factor()

sections <- table_dfs$section %>% filter(start_time >= restart_date, mturk_id %>% startsWith("A"))
sections$section <- sections$section %>% as.factor()
sections$protocol <- sections$protocol %>% ordered(levels=c("none", "placebic", "actionable"))
sections$start_time <- sections$start_time %>% as.POSIXct()
sections$end_time <- sections$end_time %>% as.POSIXct()

surveys <- table_dfs$survey %>% filter(timestamp >= restart_date, mturk_id %>% startsWith("A"))
surveys$timestamp <- surveys$timestamp %>% as.POSIXct()

users <- table_dfs$user %>% filter(start_time >= restart_date, mturk_id %>% startsWith("A"))
users$experiment_completed <- users$experiment_completed %>% as.logical()
users$failed_attention_checks <- users$failed_attention_checks %>% as.logical()
users$start_time <- users$start_time %>% as.POSIXct()
users$end_time <- users$end_time %>% as.POSIXct()
users$consent <- users$consent %>% as.logical()
users$protocol <- users$protocol %>% ordered(levels=c("none", "placebic", "actionable"))
users$study_duration <- users$end_time - users$start_time
users$bonus_comp <- pmax(users$compensation - 2.5, 0)

#### Obtain and clean survey data frames ####

survey_dfs <- get_survey_dfs(surveys)

demographics <- survey_dfs$demographics
demographics$age <- demographics$age %>% as.ordered()
demographics$gender <- demographics$gender %>% as.factor()
demographics$ethnicity <- demographics$ethnicity %>% as.factor()
demographics$attention.check <- demographics$attention.check %>% as.integer()
demographics$chess.skill <- demographics$chess.skill %>% ordered(levels=c("Beginner", "Intermediate", "Expert"))

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

theme_questions <- survey_dfs$theme_question

#### Dropped Users ####

dropped_ids <- users %>% filter(experiment_completed == F) %>% select(mturk_id) %>% unlist()
users %>% filter(mturk_id %in% c(dropped_ids))
demographics %>% filter(mturk_id %in% dropped_ids)
sections %>% filter(mturk_id %in% dropped_ids, section == "practice")
sections %>% filter(mturk_id %in% dropped_ids, section == "testing")
final_surveys %>% filter(mturk_id %in% dropped_ids) %>% select(mturk_id)

#### Duration ####

users$study_duration %>% as.double() %>% median(na.rm = T)
(users %>% inner_join(demographics, join_by(mturk_id)) %>% mutate(login.demo.duration = timestamp - start_time) %>% select(login.demo.duration) %>% unlist()/60) %>% median(na.rm = T)
(demographics %>% inner_join(sections, join_by(mturk_id)) %>% filter(section == "practice") %>% mutate(add.info = start_time - timestamp) %>% select(add.info) %>% unlist()/60) %>% as.double() %>% median(na.rm = T)
(sections %>% filter(section == "practice") %>% select(duration) %>% unlist()/60000) %>% median(na.rm = T)
(sections %>% filter(section == "testing") %>% select(duration) %>% unlist()/60000) %>% median(na.rm = T)
(sections %>% inner_join(final_surveys, join_by(mturk_id)) %>% mutate(final_survey.duration = timestamp - end_time) %>% select(final_survey.duration) %>% unlist()/60) %>% median(na.rm = T)

#### Bonus Compensation ####

users %>% 
  select(mturk_id, completion_code, bonus_comp) %>% 
  filter(bonus_comp > 0) %>%
  arrange(mturk_id)

#### Protocols ####

users %>% select(protocol) %>% table()
users %>% filter(experiment_completed) %>% select(protocol) %>% table()

#### Demographics ####

demographics$chess.skill %>% table()

sections %>% 
  filter(section == "testing") %>% 
  inner_join(demographics, join_by(mturk_id)) %>% 
  ggplot(aes(x = chess.skill, y = successes)) + 
  geom_boxplot() + 
  ylab("successes")

#### Feedback ####

feedback %>% select(text, mturk_id) %>% print(n = 500)

#### Performance: Score ####

# Correlation between practice and testing
# Progression during practice or testing
# Bonus per puzzle
# Scale within puzzle

# Data wrangling
puzzle_stats <- moves %>% 
  inner_join(users, join_by(mturk_id)) %>% 
  group_by(mturk_id, section_id, puzzle_id, protocol, experiment_completed) %>% 
  summarize(
    num_moves = n(),
    num_seconds = sum(duration)/1000,
    num_correct = sum(!mistake),
    score = 1/sqrt(num_moves*num_seconds)
  ) %>% 
  inner_join(sections, join_by(mturk_id, section_id == id), suffix = c(".move", ".section")) %>% 
  rename(protocol.user = protocol.move) %>% 
  ungroup()
puzzle_stats.practice <- puzzle_stats %>% filter(section == "practice")
puzzle_stats.testing <- puzzle_stats %>% filter(section == "testing")
# Data filtering
max_moves <- 12
max_seconds <- 300

puzzle_stats.filtered <- puzzle_stats %>% filter(num_moves <= max_moves, num_seconds <= max_seconds, num_correct == 2)
puzzle_stats.filtered.practice <- puzzle_stats.filtered %>% filter(section == "practice")
puzzle_stats.filtered.testing <- puzzle_stats.filtered %>% filter(section == "testing")

nrow(puzzle_stats.filtered.practice) / nrow(puzzle_stats.practice)
nrow(puzzle_stats.filtered.testing) / nrow(puzzle_stats.testing)

puzzle_stats %>% ggplot(aes(x = score, fill = section)) + 
  geom_histogram(position = "identity", alpha = 0.5, bins = 30) + 
  xlim(0,.4) + ylim(0,125) + 
  ggtitle("Score Distribution") + 
  theme(legend.position = c(.75,.75))
puzzle_stats.filtered %>% ggplot(aes(x = score, fill = section)) + 
  geom_histogram(position = "identity", alpha = 0.5, bins = 30) + 
  xlim(0,.4) + ylim(0,125) + 
  ggtitle("Filtered Score Distribution") + 
  theme(legend.position = c(.75,.75))
# Box plots
puzzle_stats.filtered.practice %>% ggplot(aes(x = protocol.user, y = score)) + 
  geom_boxplot() + 
  ylim(0,.4) + 
  ggtitle("Filtered Practice Score Distribution by Protocol")
puzzle_stats.filtered.testing %>% ggplot(aes(x = protocol.user, y = score)) + 
  geom_boxplot() + 
  ylim(0,.4) + 
  ggtitle("Filtered Testing Score Distribution by Protocol")
# Tests
anova.score.few.practice <- aov(score ~ protocol.user, data = puzzle_stats.filtered.practice)
tukey.score.few.practice <- TukeyHSD(anova.score.few.practice)

anova.score.few.testing <- aov(score ~ protocol.user, data = puzzle_stats.filtered.testing)
tukey.score.few.testing <- TukeyHSD(anova.score.few.testing)
# Stats
anova.score.few.practice %>% summary()
tukey.score.few.practice
tukey.score.few.practice %>% plot()
title(main = "Filtered practice scores", line = 1)

anova.score.few.testing %>% summary()
tukey.score.few.testing
tukey.score.few.testing %>% plot()
title(main = "Filtered testing scores", line = 1)

#### Performance: Bonus Compensation ####

# Data wrangling
protocol_users <- users %>% filter(!is.na(protocol))
# Data filtering
protocol_users %>% select(bonus_comp) %>% unlist() %>% hist()
protocol_users.bonus <- protocol_users %>% filter(bonus_comp > 0)
protocol_users.bonus %>% select(bonus_comp) %>% unlist() %>% hist()
nrow(protocol_users.bonus) / nrow(protocol_users)
# Box plots
protocol_users %>% ggplot(aes(x = protocol, y = bonus_comp)) + geom_boxplot()
protocol_users.bonus %>% ggplot(aes(x = protocol, y = bonus_comp)) + geom_boxplot()
# Tests
anova.bonus_comp.all <- aov(bonus_comp ~ protocol, data = protocol_users)
anova.bonus_comp.few <- aov(bonus_comp ~ protocol, data = protocol_users.bonus)
tukey.bonus_comp.all <- TukeyHSD(anova.bonus_comp.all)
tukey.bonus_comp.few <- TukeyHSD(anova.bonus_comp.few)
# Stats
anova.bonus_comp.all %>% summary()
anova.bonus_comp.few %>% summary()
tukey.bonus_comp.all
tukey.bonus_comp.few
tukey.bonus_comp.all %>% plot()
title(main = "bonus compensation (all)", line = 1)
tukey.bonus_comp.few %>% plot()
title(main = "bonus compensation (few)", line = 1)

#### Performance: Theme Questions ####

# Data Wrangling
puzzle_theme_data <- puzzle_stats %>% 
  inner_join(theme_questions, join_by(mturk_id, puzzle_id)) %>% 
  group_by(mturk_id, protocol.user) %>% 
  summarize(num_themes_correct = sum(correct), count = n(), correct_theme_ratio = num_themes_correct/count) %>% 
  ungroup()
# Data filtering
puzzle_theme_data.few <- puzzle_theme_data %>% filter(count == 5)
# Box plots
puzzle_theme_data %>% ggplot(aes(x = protocol.user, y = num_themes_correct)) + geom_boxplot()
puzzle_theme_data.few %>% ggplot(aes(x = protocol.user, y = num_themes_correct)) + geom_boxplot()
# Tests
anova.theme_data.all <- aov(num_themes_correct ~ protocol.user, data = puzzle_theme_data)
anova.theme_data.few <- aov(num_themes_correct ~ protocol.user, data = puzzle_theme_data.few)
tukey.theme_data.all <- TukeyHSD(anova.theme_data.all)
tukey.theme_data.few <- TukeyHSD(anova.theme_data.few)
# Stats
anova.theme_data.all %>% summary()
anova.theme_data.few %>% summary()
tukey.theme_data.all
tukey.theme_data.few
tukey.theme_data.all %>% plot()
title(main = "tactic answers (all)", line = 1)
tukey.theme_data.few %>% plot()
title(main = "tactic answers (few)", line = 1)

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
final_surveys.averaged %>% ggplot(aes(x = protocol, y = sat.agent)) +
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

anova.sat.agent <- aov(sat.agent ~ protocol, data = final_surveys.averaged)
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
