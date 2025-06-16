# ----- packages -----

library(xml2)
library(tidyverse)
library(rvest)
library(purrr)
library(httr)
library(lubridate)

# ----- get a set of urls -----

# just to provide wiki url
generate_url <- function(date) {

  url <-
    if_else(year(date) == 2019, if_else(month(date) == 11,
                                        "https://en.wikipedia.org/wiki/Opinion_polling_for_the_November_2019_Spanish_general_election",
                                        "https://en.wikipedia.org/wiki/Opinion_polling_for_the_April_2019_Spanish_general_election"),
            paste0("https://en.wikipedia.org/wiki/Opinion_polling_for_the_", year(date), "_Spanish_general_election"))

  return(url)
}

# just for congress
url_historical_surveys <-
  dates_elections_spain |>
  filter(cod_elec == "02") |>
  select(-topic) |>
  mutate("url_survey" = generate_url(date))

# ----- get a set of party names by date -----

# conditional_extraction <- function(node) {
#
#   has_file_span <- xml_find_all(node, ".//span[contains(@typeof, 'mw:File')]")
#
#   # img
#   if (length(has_file_span) > 0) {
#
#     node |>
#       xml_find_first(".//a")  |>
#       xml_attr("title")
#
#   } else { # text
#
#     node  |>
#       xml_text()  |>
#       str_trim()
#
#   }
# }
# extract_parties <- function(url) {
#
#   nodes <- url  |>
#     read_html()  |>
#     html_element("table")  |>
#     xml_find_all(".//th[contains(@style, 'width:35px') or contains(@style, 'width:43px') or contains(@style, 'width:40px')]")
#
#   return(map_chr(nodes, conditional_extraction))
#
# }
#
# url_historical_surveys <-
#   url_historical_surveys |>
#   mutate("parties" = map(url_survey, extract_parties))

usethis::use_data(url_historical_surveys, overwrite = TRUE,
                  compress = "gzip")
# write_csv(url_historical_surveys, "./data/url_historical_surveys.csv")
