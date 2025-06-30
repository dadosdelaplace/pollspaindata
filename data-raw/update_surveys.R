# ----- packages -----

library(xml2)
library(tidyverse)
library(rvest)
library(purrr)
library(glue)
library(httr)
library(lubridate)
library(stringi)
library(pollspain)

source("./data-raw/preproc_surveys_functions.R")

# ----- historical data -----
url <- "https://raw.githubusercontent.com/dadosdelaplace/pollspaindata/main/data/historical_surveys.rda"
temp <- tempfile(fileext = ".rda")
download.file(url, temp, mode = "wb")
load(temp)
next_date <-
  historical_surveys |>
  summarise("max_date" = as_date(max(str_sub(id_elec, start = 4))) + years(4))  |>
  pull(max_date)

# ----- update dataset -----

# Current link
url <- "https://en.wikipedia.org/wiki/Opinion_polling_for_the_next_Spanish_general_election"

new_polling_data <-
  extract_polling_data(url, "Next elections")

# The list names are the table years (as strings) – convert to numeric
years <- as.numeric(names(new_polling_data))

# id_elec
new_polling_data <-
  new_polling_data |>
  map(function(x) {
    x |>
      mutate("id_elec" = glue("02-{year(next_date)}-NA-NA"),
             .before = everything()) })

# Clean each table using the heavy 'clean_rows()' routine
clean_new_polling_data <- map2(new_polling_data, years, clean_rows)

new_polling_data <- bind_rows(clean_new_polling_data)

# Pivot to long format and harmonise party names
party_cols <-
  names(new_polling_data)[ (match("sample_size", names(new_polling_data)) + 1) : ncol(new_polling_data) ]
party_cols <- setdiff(party_cols, "Lead")

new_polling_data <-
  new_polling_data |>
  select(-Lead) |>
  pivot_longer(cols = all_of(party_cols),
               names_to = "abbrev_candidacies", values_to = "estimated_voting") |>
  drop_na(estimated_voting)

new_polling_data <- new_polling_data |>
  mutate(abbrev_candidacies = abbrev_candidacies |>
           str_to_upper() |>
           stri_trans_general("Latin-ASCII") |>
           str_replace_all("['`´]", "") |>
           stri_enc_toutf8())

new_polling_data <- new_polling_data |>
  mutate(abbrev_candidacies = case_when(
    grepl("CCA|CC-NCA", abbrev_candidacies)          ~ "CC", # Coalición Canaria
    grepl("PODEMOS", abbrev_candidacies)             ~ "PODEMOS", # Podemos
    grepl("ERC", abbrev_candidacies)                 ~ "ERC", # Esquerra Republiana de Catalunya
    grepl("MAS PAIS", abbrev_candidacies)            ~ "MP", # Más País
    grepl("JXCAT|JUNTS", abbrev_candidacies)         ~ "JXCAT-JUNTS", # Junts
    grepl("BILDU", abbrev_candidacies)               ~ "EH-BILDU", # Bildu
    grepl("NA+", abbrev_candidacies)                 ~ "NA-SUMA", # Navarra Suma
    grepl("PDECAT", abbrev_candidacies)              ~ "PDECAT-E-CIU", # Partido Demócratra Europeo Catalán
    grepl("EV", abbrev_candidacies)                  ~ "BLOC-EV", # Bloc Nacionalista Valencia
    grepl("^IU$|IU-", abbrev_candidacies)            ~ "IU", #Izquierda Unida
    grepl("NI/IC", abbrev_candidacies)               ~ "ICV", #Iniciativa per Catalunya
    grepl("^EA$|EE", abbrev_candidacies)             ~ "EA-EUE", # Eusko Alkartasuna - Euskal Ezquerra
    grepl("^PA$", abbrev_candidacies)                ~ "PAR", # Partido Aragonés
    grepl("^AP$", abbrev_candidacies)                ~ "AP-PDP-PL", # Alianza Popular
    grepl("PAD", abbrev_candidacies)                 ~ "PS", # Partido de Acción Democrática? We do not have it in the dictionary
    TRUE                                 ~ abbrev_candidacies
  ))

new_polling_data <-
  new_polling_data |>
  mutate("polling_firm" =
           str_remove_all(iconv(polling_firm, from = "UTF-8", to = "ASCII//TRANSLIT"),
                          "'"),
         "id_survey" =
           paste0(polling_firm, "-", fieldwork_start, "-",
                  fieldwork_end),
         .before = everything())

# Summarise equal surveys (same pollfirm, same fieldwork date -> same id_survey)
new_polling_data <-
  new_polling_data |>
  mutate("estimated_voting" = mean(estimated_voting, na.rm = TRUE),
         .by = c(id_survey, abbrev_candidacies)) |>
  distinct(id_survey, abbrev_candidacies, .keep_all = TRUE)

# Remove elections results
new_polling_data <-
  new_polling_data |>
  filter(!str_detect(str_to_upper(id_survey), "ELECTION"))

# ----- wide -----
new_polling_data_wide <-
  new_polling_data |>
  pivot_wider(names_from = "abbrev_candidacies",
              values_from = "estimated_voting")


# ----- UTF-8 -----

new_polling_data <-
  new_polling_data |>
  mutate(across(where(is.character), \(x) enc2utf8(x)))

new_polling_data_wide <-
  new_polling_data_wide |>
  mutate(across(where(is.character), \(x) enc2utf8(x)))

# ----- join new data ------



new_surveys <-
  new_polling_data |>
  anti_join(historical_surveys, by = "id_survey")

# update_surveys <-
#   historical_surveys |>
#


# if (!file.exists("data/next_election_polling_data.rda")){
#
#   next_election_polling_data <- new_polling_data
#
#   usethis::use_data(next_election_polling_data, overwrite = TRUE,
#                     compress = "xz")
#
# } else if (nrow(new_polling_data) > nrow(next_election_polling_data)) {
#
#   next_election_polling_data <- new_polling_data
#
#
#   usethis::use_data(next_election_polling_data, overwrite = TRUE,
#                     compress = "xz")
#
# }
