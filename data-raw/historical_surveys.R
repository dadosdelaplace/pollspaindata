# ----- packages -----

library(xml2)
library(tidyverse)
library(rvest)
library(purrr)
library(httr)
library(lubridate)
library(stringi)
library(pollspain)

source("./data-raw/preproc_surveys_functions.R")

# ----- historical dataset -----

# Pipeline to build the full historical data set

years <- c(2023, 2019, 2016, 2015,
           2011, 2008, 2004, 2000, 1996, 1993, 1989, 1986, 1982)

urls <- unlist(map(years, generate_url))

# 2019 appears twice in urls; create a matching vector of years (one per url)

years <- c(2023, 2019, 2019, 2016, 2015,
           2011, 2008, 2004, 2000, 1996, 1993, 1989, 1986, 1982)

historical_surveys <- map2(urls, years, extract_polling_data)

# Add election ids with the use of dates_elections_spain

id_elecs <- dates_elections_spain |>
  filter(cod_elec == "02") |>
  mutate(id_elec = paste(cod_elec, date, sep = "-")) |>
  pull(id_elec) |>
  rev()


historical_surveys <- map2(
  historical_surveys,
  id_elecs,
  \(sublist, codes) {
    map(sublist, function(x) {mutate(x, id_elec = codes, .before = everything())})
  }
)

# Adding the year of the surveys

years2 <- c(2019, 2020, 2021, 2022, 2023, 2023, 2023, 2019, 2016,
            2017, 2018, 2019, 2016, 2011, 2012, 2013, 2014, 2015,
            2011, 2008, 2004, 2000, 1996, 1993, 1989, 1986, 1982)

clean_historical_surveys <- map2(flatten(historical_surveys), years2, clean_rows)


historical_surveys <- bind_rows(clean_historical_surveys)

# Pivot to long format and harmonise party names

historical_surveys <- historical_surveys |>
  pivot_longer(cols = c(PSOE:TE, Junts:PAD),            # all party columns
               names_to = "abbrev_candidacies",
               values_to = "estimated_porc_ballots") |>
  drop_na(estimated_porc_ballots) |>
  mutate(
    abbrev_candidacies = str_to_upper(abbrev_candidacies) |>
      stri_trans_general("Latin-ASCII") |>
      str_replace_all("['`´]", "") |>
      stri_enc_toutf8()
  ) |>
  # Normalise variants
  mutate(abbrev_candidacies = case_when(
    grepl("UPN", abbrev_candidacies) & id_elec != "02-2023-07-24"        ~ "UPN-PP", # Unión del Pueblo Navarro
    grepl("CCA|CC-NCA", abbrev_candidacies)          ~ "CC-NC", # Coalición Canaria
    grepl("PODEMOS", abbrev_candidacies)             ~ "PODEMOS", # Podemos
    grepl("ERC", abbrev_candidacies)                 ~ "ERC", # Esquerra Republiana de Catalunya
    grepl("MAS PAIS", abbrev_candidacies)            ~ "MP", # Más País
    grepl("JXCAT|JUNTS", abbrev_candidacies)         ~ "JXCAT-JUNTS", # Junts
    grepl("BILDU", abbrev_candidacies)               ~ "EH-BILDU", # Bildu
    grepl("NA+", abbrev_candidacies)                 ~ "NA-SUMA", # Navarra Suma
    grepl("PDECAT", abbrev_candidacies)              ~ "PDECAT-E-CIU", # Partido Demócratra Europeo Catalán
    grepl("^IU$|IU-", abbrev_candidacies)            ~ "IU", #Izquierda Unida
    grepl("NI/IC", abbrev_candidacies)               ~ "ICV", #Iniciativa per Catalunya
    grepl("^EA$|EE", abbrev_candidacies)             ~ "EA-EUE", # Eusko Alkartasuna - Euskal Ezquerra
    grepl("^PA$", abbrev_candidacies)                ~ "PAR", # Partido Aragonés
    grepl("^AP$", abbrev_candidacies)                ~ "AP-PDP-PL", # Alianza Popular
    TRUE                                 ~ abbrev_candidacies
  ))
# We have to also check the ones that appear as CDC, UN and PSP

# Create an id for each survey
historical_surveys <-
  historical_surveys |>
  mutate("polling_firm" =
           str_remove_all(iconv(polling_firm, from = "UTF-8", to = "ASCII//TRANSLIT"),
                          "'"),
         "id_survey" =
           paste0(polling_firm, "-", fieldwork_start, "-",
                  fieldwork_end),
         .before = everything()) |>
  select(-Lead)

# Summarise equal surveys (same pollfirm, same fieldwork date -> same id_survey)
historical_surveys <-
  historical_surveys |>
  mutate("estimated_porc_ballots" = mean(estimated_porc_ballots, na.rm = TRUE),
         .by = c(id_survey, abbrev_candidacies)) |>
  distinct(id_survey, abbrev_candidacies, .keep_all = TRUE)

# ----- wide -----
historical_surveys_wide <-
  historical_surveys |>
  pivot_wider(names_from = "abbrev_candidacies",
              values_from = "estimated_porc_ballots",
              values_fn = sum,
              values_fill = 0)

# ----- UTF-8 -----

historical_surveys <-
  historical_surveys |>
  mutate(across(where(is.character), \(x) enc2utf8(x)))

historical_surveys_wide <-
  historical_surveys_wide |>
  mutate(across(where(is.character), \(x) enc2utf8(x)))

# historical_surveys |> summarise("n" = n(), .by = c(id_survey, abbrev_candidacies)) |> filter(n > 1)

# ----- use data -----
usethis::use_data(historical_surveys, overwrite = TRUE,
                  compress = "xz")
usethis::use_data(historical_surveys_wide, overwrite = TRUE,
                  compress = "xz")
