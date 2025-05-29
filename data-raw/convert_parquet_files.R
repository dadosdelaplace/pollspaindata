
archivos_csv <-
  list.files(path = "./inst/extdata/", full.names = TRUE)

for (i in 1:length(archivos_csv)) {

  aux <- read_csv(file = archivos_csv[i])
  write_parquet(aux, glue("{str_remove_all(str_remove_all(archivos_csv[i], './inst/extdata//'), '.csv.gz')}.parquet"))
}
