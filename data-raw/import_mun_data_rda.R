

# ----- packages -----

library(tidyverse)
library(glue)
library(lubridate)
library(crayon)
source("./R/import_raw_data_MIR.R")
source("./R/utils.R")
load("./data/dates_elections_spain.rda")
load("./data/cod_INE_mun.rda")


# ----- import mun files (prefix 05) from MIR -----

congress_elec <-
  dates_elections_spain |>
  filter(cod_elec == "02") |>
  drop_na(cod_elec, type_elec, year) |>
  distinct(type_elec, date, .keep_all = TRUE)

for (i in 1:nrow(congress_elec)) {

  raw_mun_congress <-
    congress_elec |>
    slice(i) |>
    reframe(import_raw_mun_MIR_files(type_elec, year = NULL, date = date, verbose = FALSE))
  char_month <- str_pad(congress_elec$month[i], width = "2", pad = "0")

  write_csv(raw_mun_congress,
            file = glue("./data/02-congress/02{congress_elec$year[i]}{char_month}/raw_mun_data_congress_{congress_elec$year[i]}_{char_month}.csv"))

  save(raw_mun_congress,
       file = glue("./data/02-congress/02{congress_elec$year[i]}{char_month}/raw_mun_data_congress_{congress_elec$year[i]}_{char_month}.rda"))
}

#
# senate_elec <-
#   dates_elections_spain |>
#   filter(cod_elec == "03") |>
#   drop_na(cod_elec, type_elec, year) |>
#   distinct(type_elec, date, .keep_all = TRUE)
#
# for (i in 1:nrow(senate_elec)) {
#
#   raw_mun_senate <-
#     senate_elec |>
#     slice(i) |>
#     reframe(import_raw_mun_MIR_files(type_elec, year = NULL,
#                                      date = date, verbose = FALSE))
#   char_month <- str_pad(senate_elec$month[i], width = "2", pad = "0")
#   save(raw_mun_senate,
#        file = glue("./data/03-senate/03{congress_elec$year[i]}{char_month}/raw_mun_data_senate_{congress_elec$year[i]}_{char_month}.rda"))
# }
#
#
#
