# ----- packages -----

library(tidyverse)
library(purrr)
library(lubridate)
library(pollspain)

# ----- loop dates -----

dates <-
  as_date(c("1982-10-28", "1986-06-22", "1989-10-29", "1993-06-06",
            "1996-03-03", "2000-03-12", "2004-03-14", "2008-03-09",
            "2011-11-20", "2015-12-20", "2016-06-26", "2019-04-28",
            "2019-11-10", "2023-07-24"))

for (i in 1:length(dates)) {

  summary_tb <-
    summary_election_data(type_elec = "congress",
                          date = dates[i], by_parties = TRUE,
                          level = "all",
                          short_version = FALSE,
                          verbose = FALSE) |>
    mutate(across(where(is.character), \(x) enc2utf8(x)))

  file_name <- paste0("summary_elec_all_", dates[i], ".rda")
  usethis::use_data(summary_tb, overwrite = TRUE,
                    path = file.path("inst/extdata/summary_elec/", file_name),
                    compress = "xz")

  summary_tb <-
    summary_election_data(type_elec = "congress",
                          date = dates, by_parties = TRUE,
                          level = "ccaa",
                          short_version = FALSE,
                          verbose = FALSE) |>
    mutate(across(where(is.character), \(x) enc2utf8(x)))

  file_name <- paste0("summary_elec_ccaa_", dates[i], ".rda")
  usethis::use_data(summary_tb, overwrite = TRUE,
                    path = file.path("inst/extdata/summary_elec/", file_name),
                    compress = "xz")

  summary_tb <-
    summary_election_data(type_elec = "congress",
                          date = dates, by_parties = TRUE,
                          level = "prov",
                          short_version = FALSE,
                          verbose = FALSE) |>
    mutate(across(where(is.character), \(x) enc2utf8(x)))

  file_name <- paste0("summary_elec_prov_", dates[i], ".rda")
  usethis::use_data(summary_tb, overwrite = TRUE,
                    path = file.path("inst/extdata/summary_elec/", file_name),
                    compress = "xz")
}
