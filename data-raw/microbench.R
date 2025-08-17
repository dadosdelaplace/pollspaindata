library(arrow)
library(bench)
library(tidyverse)

files_parquet <- list.files("inst/extdata", pattern = "raw_candidacies_poll.+\\.parquet$", recursive = TRUE, full.names = TRUE)

files_rda <- list.files("data", pattern = "raw_candidacies.+\\.rda$", recursive = TRUE, full.names = TRUE)
time_one <- function(path, formato, iterations = 5) {
  bm <- if (formato == "parquet") {
    bench::mark(read_parquet(path), iterations = iterations, check = FALSE) |>
      mutate(elec = str_extract(basename(path), "\\d{4}_\\d{2}"), method = "parquet") }
  else {
    bench::mark(load(path), iterations = iterations, check = FALSE) |>
      mutate(elec = str_extract(basename(path), "\\d{4}_\\d{2}"), method = "rda") }
  }

res <- bind_rows( map_dfr(files_parquet, ~time_one(.x, "parquet", iterations = 10)),
                  map_dfr(files_rda, ~time_one(.x, "rda", iterations = 10)) )

cmp <- res %>% select(elec, median, mem_alloc, total_time, method) |>
  pivot_wider(id_cols = elec,
              names_from = method,
              values_from = c(median, mem_alloc, total_time),
              names_glue = "{.value}_{method}"
              )
