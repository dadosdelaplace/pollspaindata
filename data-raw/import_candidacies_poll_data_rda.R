

# ----- packages -----

library(tidyverse)
library(glue)
library(lubridate)
library(crayon)
source("./R/import_raw_data_MIR.R")
source("./R/utils.R")

load("./data/dates_elections_spain.rda")
load("./data/cod_INE_mun.rda")

# ----- import candidacies ballots files (prefix 10) from MIR -----

congress_elec <-
  dates_elections_spain |>
  filter(cod_elec == "02") |>
  drop_na(cod_elec, type_elec, year) |>
  distinct(type_elec, date, .keep_all = TRUE)

for (i in 1:nrow(congress_elec)) {

  raw_candidacies_poll_congress <-
    congress_elec |>
    slice(i) |>
    reframe(import_raw_candidacies_poll_file(type_elec, year = NULL, date = date, verbose = FALSE))
  char_month <- str_pad(congress_elec$month[i], width = "2", pad = "0")

  write_csv(raw_candidacies_poll_congress,
            file = glue("./data/02-congress/02{congress_elec$year[i]}{char_month}/raw_candidacies_poll_congress_{congress_elec$year[i]}_{char_month}.csv"))

  save(raw_candidacies_poll_congress,
       file = glue("./data/02-congress/02{congress_elec$year[i]}{char_month}/raw_candidacies_poll_congress_{congress_elec$year[i]}_{char_month}.rda"))
}
