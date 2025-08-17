library(arrow)
library(bench)


bench::mark(
  parquet = read_parquet("inst/extdata/raw_candidacies_poll_congress_2004_03.parquet"),
  rda = { e <- new.env(); load("data/02-congress/02200403/raw_candidacies_poll_congress_2004_03.rda", envir = e); e[[ls(e)[1]]] },
  iterations = 5, check = FALSE
)
