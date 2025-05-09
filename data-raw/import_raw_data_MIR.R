

# Data extracted from https://infoelectoral.interior.gob.es/opencms/es/elecciones-celebradas/area-de-descargas/

# Import raw candidacies
import_raw_candidacies_file <-
  function(type_elec, year, date = NULL,
           base_url =
             "https://infoelectoral.interior.gob.es/estaticos/docxl/apliextr/",
           encoding = "Latin1", starts = c(1, 3, 7, 9, 15, 65, 215, 221, 227),
           ends = c(2, 6, 8, 14, 64, 214, 220, 226, 232), verbose = TRUE) {

    # Check if verbose is correct
    if (!is.logical(verbose) | is.na(verbose)) {

      stop(red("😵 `verbose` argument should be a TRUE/FALSE logical flag."))

    }

    if (verbose) {

      message(yellow("🔎 Check if parameters are allowed..."))
      Sys.sleep(1/20)

    }

    # for the moment, just congress election
    if (!all(type_elec %in% c("congress", "senate"))) {

      stop(red("😵 The package is currently under development so, for the moment, it only allows access to congress and senate data."))

    }

    # check if date is correct
    if (is.null(date)) {
      if (!is.numeric(year)) {
        stop(red("😵 If no date was provided, `year` should be a numerical variable."))
      }
    } else {

      date <- as_date(date)
      year <- year(date)
      if (is.na(date)) {
        stop(red("😵 If date was provided, `date` should be in format '2000-01-01' (%Y-%m-%d)"))
      }
    }

    # Check if the inputs are vectors
    if (!is.vector(type_elec) | !is.vector(year)) {

      stop(red("😵 `type_elec` and `year` must be vectors."))

    }

    # Check: if base_url and encoding are valid
    if (!is.character(base_url) | !is.character(encoding)) {

      stop(red("😵 Parameters 'base_url' and 'encoding' must be character"))

    }

    # Check: if lengths of starts and ends are equal
    if (length(starts) != length(ends)) {

      stop(red("😵 Length of vectors 'starts' and 'ends' must be equal"))

    }

    # Design a tibble with all elections asked by user
    # Ensure input parameters are vectors
    if (is.null(date)) {

      asked_elections <-
        expand_grid(as.vector(type_elec), as.vector(year))
      names(asked_elections) <- c("type_elec", "year")
      asked_elections <-
        asked_elections |>
        distinct(type_elec, year)

    } else {

      asked_elections <-
        expand_grid(as.vector(type_elec), date) |>
        mutate("year" = year(date))
      names(asked_elections) <- c("type_elec", "date", "year")
      asked_elections <-
        asked_elections |>
        distinct(type_elec, date, year)
    }

    asked_elections <-
      asked_elections |>
      mutate("cod_elec" = type_to_code_election(as.vector(type_elec)),
             .before = everything())

    # Check if elections required are allowed
    allowed_elections <-
      dates_elections_spain |>
      inner_join(asked_elections,
                 by = c("cod_elec", "type_elec", "date"),
                 suffix = c("", ".rm")) |>
      select(-contains(".rm")) |>
      distinct(cod_elec, type_elec, date, .keep_all = TRUE)
    if (allowed_elections |> nrow() == 0) {

      stop(red(glue("😵 No {type_elec} elections are available in date provided. Please, be sure that arguments are right")))

    } else if ((allowed_elections |> nrow()) > 1 & is.null(date)) {

      message(yellow(glue("⚠️ Multiple {type_elec} elections are available in date provided. If you only want one of them, please provide a specific date in the `date` argument")))

    }

    # Build the set of url (.zip file)
    url <- glue("{base_url}{allowed_elections$cod_elec}{allowed_elections$year}{str_pad(allowed_elections$month, pad = '0', width = 2)}_MESA.zip")

    raw_file <- tibble()
    for (i in 1:length(url)) {

      # Build temporal directory
      temp <- tempfile(tmpdir = tempdir(), fileext = ".zip")
      download.file(url[i], temp, mode = "wb")
      unzip(temp, overwrite = TRUE, exdir = tempdir())

      # Import raw data (files 03 from MIR)
      path <-
        glue("{tempdir()}/03{allowed_elections$cod_elec[i]}{str_sub(allowed_elections$year[i], start = 3, end = 4)}{str_pad(allowed_elections$month[i], pad = '0', width = 2)}.DAT")
      raw_file <-
        as_tibble(read_lines(file = path,
                             locale = locale(encoding = encoding))) |>
        bind_rows(raw_file)

      # Delete temporary dir
      try(file.remove(list.files(tempdir(), full.names = TRUE, recursive = TRUE)),
          silent = TRUE)
    }

    # Process variables following the instructions of register
    candidacies <-
      raw_file |>
      mutate(cod_elec = str_sub(value, start = starts[1], end = ends[1]),
             type_elec = type_elec,
             year = as.numeric(str_sub(value, starts[2], end = ends[2])),
             month =
               as.numeric(str_sub(value, start = starts[3], end = ends[3])),
             id_candidacies =
               str_trim(str_sub(value, start = starts[4], end = ends[4])),
             abbrev_candidacies =
               str_to_upper(str_trim(str_sub(value, start = starts[5],
                                             end = ends[5]))),
             name_candidacies =
               str_to_upper(str_trim(str_sub(value, start = starts[6],
                                             end = ends[6]))),
             cod_candidacies_prov =
               str_trim(str_sub(value, start = starts[7], end = ends[7])),
             id_candidacies_ccaa =
               str_trim(str_sub(value, start = starts[8], end = ends[8])),
             id_candidacies_nat =
               str_trim(str_sub(value, start = starts[9], end = ends[9]))) |>
      select(-value, -cod_candidacies_prov) |>
      select(where(function(x) {
        !all(is.na(x))
      }))

    # Join with dates of elections
    candidacies <-
      candidacies |>
      left_join(dates_elections_spain |> select(-topic),
                by = c("cod_elec", "type_elec", "year", "month"))  |>
      select(-year, -month, -day)

    # Rename and relocate
    candidacies <-
      candidacies |>
      rename(date_elec = date) |>
      relocate(date_elec, .after = type_elec)

    # output
    return(candidacies)
  }

# Import raw mun files
import_raw_mun_MIR_files <-
  function(type_elec, year, date = NULL,
           base_url =
             "https://infoelectoral.interior.gob.es/estaticos/docxl/apliextr/",
           encoding = "Latin1",
           starts = c(1, 3, 7, 10, 12, 14, 17, 19, 120, 123,
                      129, 137, 142, 150, 158),
           ends = c(2, 6, 8, 11, 13, 16, 18, 118, 122, 125,
                    136, 141, 149, 157, 165), verbose = TRUE) {

    # Check if verbose is correct
    if (!is.logical(verbose) | is.na(verbose)) {

      stop(red("😵 `verbose` argument should be a TRUE/FALSE logical flag."))

    }

    if (verbose) {

      message(yellow("🔎 Check if parameters are allowed..."))
      Sys.sleep(1/20)

    }

    # for the moment, just congress election
    if (!all(type_elec %in% c("congress", "senate"))) {

      stop(red("😵 The package is currently under development so, for the moment, it only allows access to congress and senate data."))

    }

    # check if date is correct
    if (is.null(date)) {
      if (!is.numeric(year)) {
        stop(red("😵 If no date was provided, `year` should be a numerical variable."))
      }
    } else {

      date <- as_date(date)
      year <- year(date)
      if (is.na(date)) {
        stop(red("😵 If date was provided, `date` should be in format '2000-01-01' (%Y-%m-%d)"))
      }
    }

    # Check if the inputs are vectors
    if (!is.vector(type_elec) | !is.vector(year)) {

      stop(red("😵 `type_elec` and `year` must be vectors."))

    }

    # Check: if base_url and encoding are valid
    if (!is.character(base_url) | !is.character(encoding)) {

      stop(red("😵 Parameters 'base_url' and 'encoding' must be character"))

    }

    # Check: if lengths of starts and ends are equal
    if (length(starts) != length(ends)) {

      stop(red("😵 Length of vectors 'starts' and 'ends' must be equal"))

    }

    # Design a tibble with all elections asked by user
    # Ensure input parameters are vectors
    if (is.null(date)) {

      asked_elections <-
        expand_grid(as.vector(type_elec), as.vector(year))
      names(asked_elections) <- c("type_elec", "year")
      asked_elections <-
        asked_elections |>
        distinct(type_elec, year)

    } else {

      asked_elections <-
        expand_grid(as.vector(type_elec), date) |>
        mutate("year" = year(date))
      names(asked_elections) <- c("type_elec", "date", "year")
      asked_elections <-
        asked_elections |>
        distinct(type_elec, date, year)
    }

    asked_elections <-
      asked_elections |>
      mutate("cod_elec" = type_to_code_election(as.vector(type_elec)),
             .before = everything())

    # Check if elections required are allowed
    allowed_elections <-
      dates_elections_spain |>
      inner_join(asked_elections,
                 by = c("cod_elec", "type_elec", "date"),
                 suffix = c("", ".rm")) |>
      select(-contains(".rm")) |>
      distinct(cod_elec, type_elec, date, .keep_all = TRUE)
    if (allowed_elections |> nrow() == 0) {

      stop(red(glue("😵 No {type_elec} elections are available in {year}. Please, be sure that arguments are right")))

    } else if ((allowed_elections |> nrow()) > 1 & is.null(date)) {

      message(yellow(glue("⚠️ Multiple {type_elec} elections are available in {year}. If you only want one of them, please provide a specific date in the `date` argument")))

    }

    # Build the set of url (.zip file)
    url <- glue("{base_url}{allowed_elections$cod_elec}{allowed_elections$year}{str_pad(allowed_elections$month, pad = '0', width = 2)}_MESA.zip")

    raw_file <- tibble()
    for (i in 1:length(url)) {

      # Build temporal directory
      temp <- tempfile(tmpdir = tempdir(), fileext = ".zip")
      download.file(url[i], temp, mode = "wb")
      unzip(temp, overwrite = TRUE, exdir = tempdir())

      # Import raw data (files 05 from MIR)
      path <-
        glue("{tempdir()}/05{allowed_elections$cod_elec[i]}{str_sub(allowed_elections$year[i], start = 3, end = 4)}{str_pad(allowed_elections$month[i], pad = '0', width = 2)}.DAT")
      raw_file <-
        as_tibble(read_lines(file = path,
                             locale = locale(encoding = encoding))) |>
        bind_rows(raw_file)

      # Delete temporary dir
      try(file.remove(list.files(tempdir(), full.names = TRUE, recursive = TRUE)),
          silent = TRUE)
    }

    # Process variables following the instructions of register
    mun_file <-
      raw_file |>
      mutate(cod_elec = str_sub(value, start = starts[1], end = ends[1]),
             type_elec = type_elec,
             year =
               as.numeric(str_sub(value, starts[2], end = ends[2])),
             month =
               as.numeric(str_sub(value, start = starts[3], end = ends[3])),
             cod_MIR_ccaa =
               str_sub(value, start = starts[4], end = ends[4]),
             cod_INE_prov =
               str_sub(value, start = starts[5], end = ends[5]),
             cod_INE_mun =
               str_sub(value, start = starts[6], end = ends[6]),
             cod_mun_district =
               str_sub(value, start = starts[7], end = ends[7]),
             mun = str_trim(str_sub(value, start = starts[8], end = ends[8])),
             cod_mun_jud_district =
               str_trim(str_sub(value, start = starts[9], end = ends[9])),
             # provincial council (diputacion)
             cod_mun_prov_council =
               str_sub(value, start = starts[10], end = ends[10]),
             # Census of people who are living (CER + CERA)
             pop_res_mun =
               as.numeric(str_sub(value, start = starts[11], end = ends[11])),
             n_poll_stations =
               as.numeric(str_sub(value, start = starts[12], end = ends[12])),
             # pop_res who are allowed to vote
             census_INE_mun =
               as.numeric(str_sub(value, start = starts[13], end = ends[13])),
             # census_ine after claims
             census_counting_mun =
               as.numeric(str_sub(value, start = starts[14], end = ends[14])),
             # census CERE (census of foreigners, just for EU)
             census_CERE_mun =
               as.numeric(str_sub(value, start = starts[15],
                                  end = ends[15]))) |>
      select(-value) |>
      select(where(function(x) { !all(is.na(x)) })) |>
      mutate(id_MIR_mun =
               glue("{cod_MIR_ccaa}-{cod_INE_prov}-{cod_INE_mun}")) |>
      relocate(id_MIR_mun, .before = cod_MIR_ccaa) |>
      relocate(n_poll_stations, .before = pop_res_mun)

    # Remove municipal (non electoral) district data
    mun_file <-
      mun_file |>
      filter(cod_mun_district == "99") |>
      distinct(mun, cod_INE_mun, .keep_all = TRUE) |>
      select(-cod_mun_district)

    # Join with dates of elections
    mun_file <-
      mun_file |>
      left_join(dates_elections_spain |> select(-topic),
                by = c("cod_elec", "type_elec", "year", "month"),
                suffix = c("", ".rm")) |>
      relocate(date, .after = type_elec) |>
      rename(date_elec = date) |>
      select(-year, -day, -contains("rm"))

    # output
    return(mun_file)
  }



# Import poll stations files
import_poll_stations_MIR_files <-
  function(type_elec, year, date = NULL,
           base_url =
             "https://infoelectoral.interior.gob.es/estaticos/docxl/apliextr/",
           encoding = "Latin1",
           starts = c(1, 3, 7, 9, 10, 12, 14, 17, 19, 23, 24,
                      31, 38, 45, 52, 59, 66, 73, 80),
           ends = c(2, 6, 8, 9, 11, 13, 16, 18, 22, 23, 30,
                    37, 44, 51, 58, 65, 72, 79, 86),
           verbose = TRUE) {

    # Check if verbose is correct
    if (!is.logical(verbose) | is.na(verbose)) {

      stop(red("😵 `verbose` argument should be a TRUE/FALSE logical flag."))

    }

    if (verbose) {

      message(yellow("🔎 Check if parameters are allowed..."))
      Sys.sleep(1/20)

    }

    # for the moment, just congress election
    if (!all(type_elec %in% c("congress", "senate"))) {

      stop(red("😵 The package is currently under development so, for the moment, it only allows access to congress and senate data."))

    }

    # check if date is correct
    if (is.null(date)) {
      if (!is.numeric(year)) {
        stop(red("😵 If no date was provided, `year` should be a numerical variable."))
      }
    } else {

      date <- as_date(date)
      if (is.na(date)) {
        stop(red("😵 If date was provided, `date` should be in format '2000-01-01' (%Y-%m-%d)"))
      }
    }

    # Check if the inputs are vectors
    if (!is.vector(type_elec) | !is.vector(year)) {

      stop(red("😵 `type_elec` and `year` must be vectors."))

    }

    # Check: if base_url and encoding are valid
    if (!is.character(base_url) | !is.character(encoding)) {

      stop(red("😵 Parameters 'base_url' and 'encoding' must be character"))

    }

    # Check: if lengths of starts and ends are equal
    if (length(starts) != length(ends)) {

      stop(red("😵 Length of vectors 'starts' and 'ends' must be equal"))

    }

    # Design a tibble with all elections asked by user
    # Ensure input parameters are vectors
    if (is.null(date)) {

      asked_elections <-
        expand_grid(as.vector(type_elec), as.vector(year))
      names(asked_elections) <- c("type_elec", "year")
      asked_elections <-
        asked_elections |>
        distinct(type_elec, year)

    } else {

      asked_elections <-
        expand_grid(as.vector(type_elec), date) |>
        mutate("year" = year(date))
      names(asked_elections) <- c("type_elec", "date", "year")
      asked_elections <-
        asked_elections |>
        distinct(type_elec, date, year)
    }

    asked_elections <-
      asked_elections |>
      mutate("cod_elec" = type_to_code_election(as.vector(type_elec)),
             .before = everything())

    if (!is.null(year)) {

      # Check if elections required are allowed
      allowed_elections <-
        dates_elections_spain |>
        inner_join(asked_elections,
                   by = c("cod_elec", "type_elec", "year"),
                   suffix = c("", ".rm")) |>
        select(-contains(".rm")) |>
        distinct(cod_elec, type_elec, date, .keep_all = TRUE)

    }

    if (!is.null(date)) {

      # Check if elections required are allowed
      allowed_elections <-
        dates_elections_spain |>
        inner_join(asked_elections,
                   by = c("cod_elec", "type_elec", "date"),
                   suffix = c("", ".rm")) |>
        select(-contains(".rm")) |>
        distinct(cod_elec, type_elec, date, .keep_all = TRUE)

    }

    if (allowed_elections |> nrow() == 0) {

      stop(red(glue("😵 No {type_elec} elections are available in {year}. Please, be sure that arguments are right")))

    } else if ((allowed_elections |> nrow()) > 1 & is.null(date)) {

      message(yellow(glue("⚠️ Multiple {type_elec} elections are available in {year}. If you only want one of them, please provide a specific date in the `date` argument")))

    }

    # Build the set of url (.zip file)
    url <- glue("{base_url}{allowed_elections$cod_elec}{allowed_elections$year}{str_pad(allowed_elections$month, pad = '0', width = 2)}_MESA.zip")

    raw_file <- tibble()
    for (i in 1:length(url)) {

      # Build temporal directory
      temp <- tempfile(tmpdir = tempdir(), fileext = ".zip")
      download.file(url[i], temp, mode = "wb")
      unzip(temp, overwrite = TRUE, exdir = tempdir())

      # Import raw data (files 09 from MIR)
      path <-
        glue("{tempdir()}/09{allowed_elections$cod_elec[i]}{str_sub(allowed_elections$year[i], start = 3, end = 4)}{str_pad(allowed_elections$month[i], pad = '0', width = 2)}.DAT")
      raw_file <-
        as_tibble(read_lines(file = path,
                             locale = locale(encoding = encoding))) |>
        bind_rows(raw_file)

      # Delete temporary dir
      try(file.remove(list.files(tempdir(), full.names = TRUE, recursive = TRUE)),
          silent = TRUE)
    }


    # Process variables following the instructions of register
    poll_stations <-
      raw_file |>
      mutate(cod_elec = str_sub(value, start = starts[1], end = ends[1]),
             type_elec = type_elec,
             year =
               as.numeric(str_sub(value, starts[2], end = ends[2])),
             month =
               as.numeric(str_sub(value, start = starts[3], end = ends[3])),
             turn =
               as.numeric(str_sub(value, start = starts[4], end = ends[4])),
             cod_MIR_ccaa =
               str_trim(str_sub(value, start = starts[5], end = ends[5])),
             cod_INE_prov =
               str_trim(str_sub(value, start = starts[6], end = ends[6])),
             cod_INE_mun =
               str_trim(str_sub(value, start = starts[7], end = ends[7])),
             id_MIR_mun = glue("{cod_MIR_ccaa}-{cod_INE_prov}-{cod_INE_mun}"),
             cod_mun_district =
               str_trim(str_sub(value, start = starts[8], end = ends[8])),
             cod_sec =
               str_trim(str_sub(value, start = starts[9], end = ends[9])),
             cod_poll_station =
               str_trim(str_sub(value, start = starts[10], end = ends[10])),
             # pop_res who are allowed to vote
             census_INE =
               as.numeric(str_sub(value, start = starts[11], end = ends[11])),
             # census_ine after claims (or C.E.R.A, Spanish citizens absent)
             census_counting =
               as.numeric(str_sub(value, start = starts[12], end = ends[12])),
             # C.E.R.E (census of foreign citizens)
             census_cere =
               as.numeric(str_sub(value, start = starts[13], end = ends[13])),
             voters_cere =
               as.numeric(str_sub(value, start = starts[14], end = ends[14])),
             ballots_1 =
               as.numeric(str_sub(value, start = starts[15], end = ends[15])),
             ballots_2 =
               as.numeric(str_sub(value, start = starts[16], end = ends[16])),
             blank_ballots =
               as.numeric(str_sub(value, start = starts[17], end = ends[17])),
             invalid_ballots =
               as.numeric(str_sub(value, start = starts[18], end = ends[18])),
             party_ballots =
               as.numeric(str_sub(value, start = starts[19],
                                  end = ends[19]))) |>
      select(-value) |>
      select(where(function(x) {
        !all(is.na(x))
      }))

    # Join with dates of elections
    poll_stations <-
      poll_stations |>
      left_join(dates_elections_spain |> select(-topic),
                by = c("cod_elec", "type_elec", "year", "month")) |>
      select(-year, -month, -day)

    # Rename and relocate
    poll_stations <-
      poll_stations |>
      rename(date_elec = date) |>
      relocate(date_elec, .after = type_elec) |>
      relocate(id_MIR_mun, .after = date_elec) |>
      relocate(turn, .after = cod_poll_station)

    # C.E.R.A (census of Spanish citizens absent from Spain)
    # are asigned cod_INE_mun = "999", cod_mun_district = "09"
    # cod_sec = "0000", cod_poll_station = "U"
    # For each ccaa is summarized with cod_INE_prov = "99"
    poll_stations <-
      poll_stations |>
      # Remove summaries
      filter(!(cod_INE_prov == "99" & cod_INE_mun == "999"))

    # output
    return(poll_stations)
  }


# Import raw candidacies ballots
import_raw_candidacies_poll_file <-
  function(type_elec, year, date = NULL,
           base_url =
             "https://infoelectoral.interior.gob.es/estaticos/docxl/apliextr/",
           encoding = "Latin1",
           starts = c(1, 3, 7, 9, 10, 12, 14, 17, 19, 23, 24, 30),
           ends = c(2, 6, 8, 9, 11, 13, 16, 18, 22, 23, 29, 36),
           verbose = TRUE) {

    # Check if verbose is correct
    if (!is.logical(verbose) | is.na(verbose)) {

      stop(red("😵 `verbose` argument should be a TRUE/FALSE logical flag."))

    }

    if (verbose) {

      message(yellow("🔎 Check if parameters are allowed..."))
      Sys.sleep(1/20)

    }

    # for the moment, just congress election
    if (!all(type_elec %in% c("congress", "senate"))) {

      stop(red("😵 The package is currently under development so, for the moment, it only allows access to congress and senate data."))

    }

    # check if date is correct
    if (is.null(date)) {
      if (!is.numeric(year)) {
        stop(red("😵 If no date was provided, `year` should be a numerical variable."))
      }
    } else {

      date <- as_date(date)
      year <- year(date)
      if (is.na(date)) {
        stop(red("😵 If date was provided, `date` should be in format '2000-01-01' (%Y-%m-%d)"))
      }
    }

    # Check if the inputs are vectors
    if (!is.vector(type_elec) | !is.vector(year)) {

      stop(red("😵 `type_elec` and `year` must be vectors."))

    }

    # Check: if base_url and encoding are valid
    if (!is.character(base_url) | !is.character(encoding)) {

      stop(red("😵 Parameters 'base_url' and 'encoding' must be character"))

    }

    # Check: if lengths of starts and ends are equal
    if (length(starts) != length(ends)) {

      stop(red("😵 Length of vectors 'starts' and 'ends' must be equal"))

    }

    # Design a tibble with all elections asked by user
    # Ensure input parameters are vectors
    if (is.null(date)) {

      asked_elections <-
        expand_grid(as.vector(type_elec), as.vector(year))
      names(asked_elections) <- c("type_elec", "year")
      asked_elections <-
        asked_elections |>
        distinct(type_elec, year)

    } else {

      asked_elections <-
        expand_grid(as.vector(type_elec), date) |>
        mutate("year" = year(date))
      names(asked_elections) <- c("type_elec", "date", "year")
      asked_elections <-
        asked_elections |>
        distinct(type_elec, date, year)
    }

    asked_elections <-
      asked_elections |>
      mutate("cod_elec" = type_to_code_election(as.vector(type_elec)),
             .before = everything())

    if (!is.null(date)) {

      # Check if elections required are allowed
      allowed_elections <-
        dates_elections_spain |>
        inner_join(asked_elections,
                   by = c("cod_elec", "type_elec", "date"),
                   suffix = c("", ".rm")) |>
        select(-contains(".rm")) |>
        distinct(cod_elec, type_elec, date, .keep_all = TRUE)

    }

    if (!is.null(year)) {

      # Check if elections required are allowed
      allowed_elections <-
        dates_elections_spain |>
        inner_join(asked_elections,
                   by = c("cod_elec", "type_elec", "year"),
                   suffix = c("", ".rm")) |>
        select(-contains(".rm")) |>
        distinct(cod_elec, type_elec, date, .keep_all = TRUE)

    }

    if (allowed_elections |> nrow() == 0) {

      stop(red(glue("😵 No {type_elec} elections are available in {year}. Please, be sure that arguments are right")))

    } else if ((allowed_elections |> nrow()) > 1 & is.null(date)) {

      message(yellow(glue("⚠️ Multiple {type_elec} elections are available in {year}. If you only want one of them, please provide a specific date in the `date` argument")))

    }

    # Build the set of url (.zip file)
    url <- glue("{base_url}{allowed_elections$cod_elec}{allowed_elections$year}{str_pad(allowed_elections$month, pad = '0', width = 2)}_MESA.zip")

    raw_file <- tibble()
    for (i in 1:length(url)) {

      # Build temporal directory
      temp <- tempfile(tmpdir = tempdir(), fileext = ".zip")
      download.file(url[i], temp, mode = "wb")
      unzip(temp, overwrite = TRUE, exdir = tempdir())

      # Import raw data (files 10 from MIR)
      path <-
        glue("{tempdir()}/10{allowed_elections$cod_elec[i]}{str_sub(allowed_elections$year[i], start = 3, end = 4)}{str_pad(allowed_elections$month[i], pad = '0', width = 2)}.DAT")
      raw_file <-
        as_tibble(read_lines(file = path,
                             locale = locale(encoding = encoding))) |>
        bind_rows(raw_file)

      # Delete temporary dir
      try(file.remove(list.files(tempdir(), full.names = TRUE, recursive = TRUE)),
          silent = TRUE)
    }

    # Process variables following the instructions of register
    poll_stations_ballots <-
      raw_file |>
      mutate(cod_elec = str_sub(value, start = starts[1], end = ends[1]),
             type_elec = type_elec,
             year = as.numeric(str_sub(value, starts[2], end = ends[2])),
             month =
               as.numeric(str_sub(value, start = starts[3], end = ends[3])),
             turn =
               as.numeric(str_sub(value, start = starts[4], end = ends[4])),
             cod_MIR_ccaa =
               str_trim(str_sub(value, start = starts[5], end = ends[5])),
             cod_INE_prov =
               str_trim(str_sub(value, start = starts[6], end = ends[6])),
             cod_INE_mun =
               str_trim(str_sub(value, start = starts[7], end = ends[7])),
             id_MIR_mun =
               glue("{cod_MIR_ccaa}-{cod_INE_prov}-{cod_INE_mun}"),
             cod_mun_district =
               str_trim(str_sub(value, start = starts[8], end = ends[8])),
             cod_sec =
               str_trim(str_sub(value, start = starts[9], end = ends[9])),
             cod_poll_station =
               str_trim(str_sub(value, start = starts[10], end = ends[10])),
             id_candidacies =
               str_trim(str_sub(value, start = starts[11], end = ends[11])),
             ballots =
               as.numeric(str_sub(value, start = starts[12],
                                  end = ends[12]))) |>
      select(-value) |>
      select(where(function(x) {
        !all(is.na(x))
      }))

    # Join with dates of elections
    poll_stations_ballots <-
      poll_stations_ballots |>
      left_join(dates_elections_spain |> select(-topic),
                by = c("cod_elec", "type_elec", "year", "month")) |>
      select(-year, -month, -day)

    # Rename and relocate
    poll_stations_ballots <-
      poll_stations_ballots |>
      rename(date_elec = date) |>
      relocate(date_elec, .after = type_elec) |>
      relocate(id_MIR_mun, .after = date_elec) |>
      relocate(turn, .after = cod_poll_station)

    # Remove summaries CERA
    poll_stations_ballots <-
      poll_stations_ballots |>
      filter(!(cod_INE_prov == "99" & cod_INE_mun == "999"))

    # output
    return(poll_stations_ballots)
  }

