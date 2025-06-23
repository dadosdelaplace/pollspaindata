
# Libraries

library(xml2)
library(tidyverse)
library(rvest)
library(purrr)
library(stringdist)
library(httr)
library(stringr)
library(tibble)
library(readr)
library(lubridate)
library(stringi)

# Functions-------------------------------------------------

#------------------------------------------------------------------------------
# generate_url() ▸ Build the Wikipedia URL(s) for a given election year.
#  * 2019 has two separate elections (April & November), so it returns 2 links.
#  * All other years return a single link.
#------------------------------------------------------------------------------

generate_url <- function(years) {
  if (years == 2019) {
    c(
      "https://en.wikipedia.org/wiki/Opinion_polling_for_the_November_2019_Spanish_general_election",
      "https://en.wikipedia.org/wiki/Opinion_polling_for_the_April_2019_Spanish_general_election"
    )
  } else {
    # Generic URL pattern for every other year
    paste0("https://en.wikipedia.org/wiki/Opinion_polling_for_the_", years, "_Spanish_general_election")
  }
}

get_tables_after_voting_estimates <- function(url) { # We need to find all tables after the h4 <h4 id="Voting_intention_estimates"> but before any other h4 or higher

  # Read page and locate the <div> that wraps the <h4 id="Voting_intention_estimates">
  siblings <- url |>
    read_html() |>
    xml_find_first(".//div[h4[@id='Voting_intention_estimates']]")  |>  # starting node: has to be the parents => the div that contains <h4 id='Voting_intention_estimates'>
    xml_find_all("following-sibling::*") # get all * following sibling tables after the one we just mentioned (div of h4) (https://www.roborabbit.com/blog/mastering-xpath-using-the-following-sibling-and-preceding-sibling-axes/)

  # Find the first "big" header (div.mw-heading2, 3 or 4) that marks the end
  boundary <- which(xml_name(siblings)
                    == "div"
                    & str_detect(xml_attr(siblings, "class"), "mw-heading[234]")
  )

  if (length(boundary) > 0) {
    siblings <- siblings[1:(boundary[1] - 1)]
  }

  # Get the years for each table out of h5 id + their corresponding tables
  tables_with_years <- list()
  last_h5_id <- NULL
  current_year <- NULL

  for (i in seq_along(siblings)) {
    node <- siblings[[i]]

    # checking if there is a h5 header
    if (xml_name(node) == "div" &&
        str_detect(xml_attr(node, "class"), "mw-heading5")) {

      # extract the year
      h5_id <- node |>
        xml_find_first(".//h5") |>
        xml_attr("id")

      last_h5_id <- h5_id  # store for later

      current_year <- case_when(
        str_detect(h5_id, "^\\d{4}$") ~ as.numeric(h5_id), # 4 digits
        str_detect(h5_id, "^\\d{4}_") ~ as.numeric(str_extract(h5_id, "^\\d{4}")), # When there are paranthesis
        str_detect(h5_id, "^\\d{4}–\\d{4}$") ~ as.numeric(str_extract(h5_id, "^\\d{4}")), # When there is a year range
        TRUE ~ as.numeric(str_extract(h5_id, "\\d{4}")) # Anything else
      )
    }

    #  If the node is a table, associate it with current_year (if any)
    if (xml_name(node) == "table") {

      # If no h5 header preceded the table, attempt to infer year from the
      # "polling firm" column (first column) inside the table itself.
      if (is.null(current_year) || is.na(current_year)) {
        table_data <- tryCatch({
          html_table(node)
        }, error = function(e) NULL)

        if (!is.null(table_data) && nrow(table_data) > 1 && ncol(table_data) > 0) {
          # Look for a 4‑digit number anywhere in that first column
          for (row_i in 1:nrow(table_data)) {
            polling_firm_year <- table_data[[row_i, 1]] |>
              str_extract("[0-9]{4}") |>
              as.numeric()

            if (!is.na(polling_firm_year)) {
              current_year <- polling_firm_year
              cat(sprintf("No h5 header found, using year from polling_firm (row %d): %s\n", row_i, current_year))
              break
            }
          }
        }
      }

      # Only keep the table if we have a usable year
      if (!is.null(current_year) && !is.na(current_year)) {

        tables_with_years[[length(tables_with_years) + 1]] <- list(
          table = node,
          year = current_year,
          id = last_h5_id  # keep full h5 id as label
        )

        if (!is.null(last_h5_id)) {
          cat(sprintf("Found h5 with ID: '%s' -> Year: %s\n", last_h5_id, current_year))
          cat(sprintf("\t Found table under h5\n"))
          last_h5_id <- NULL  ## reset so the next table doesn’t reuse this id
        }

      }
    }
  }

  # Name each list element with its year (as character) for easy grouping later
  names(tables_with_years) <- map_chr(tables_with_years, function(x) {as.character(x$year)})

  return(tables_with_years)
}

#------------------------------------------------------------------------------
# extract_party_names() ▸ From every xml <table>, grab the tiny coloured‑box
# headers that contain the party names. Those <th> cells have fixed widths
# (35–43 px in Wikipedia's template).
#------------------------------------------------------------------------------


extract_party_names <- function(tables) {
  # iterate over each table
  map(tables, function(x) {
    table_node <- x$table

    # Select <th> whose inline style fixes the width to 35/40/43 px (party cells)
    nodes <- table_node |>
      xml_find_all(".//th[
                   contains(@style, 'width:35px') or
                   contains(@style, 'width:43px') or
                   contains(@style, 'width:40px')]")

    map_chr(nodes, conditional_extraction)
  })
}

# Wrapper that simply names each vector of parties with its table index
get_all_parties <- function(all_tables) {

  # get party names from each set of table nodes
  all_parties <- extract_party_names(all_tables)

  # return with names as indices since each table gets its own party names
  names(all_parties) <- seq_along(all_parties)

  return(all_parties)

}

# If the <th> contains a miniature flag/logo (span typeof="mw:File"), then the
# actual name is the title of the <a> tag; otherwise just take the plain text.
conditional_extraction <- function(node) {
  has_file_span <- xml_find_all(node, ".//span[contains(@typeof, 'mw:File')]")

  if (length(has_file_span) > 0) {
    node |>
      xml_find_first(".//a") |>
      xml_attr("title")
  } else {
    node |>
      xml_text() |>
      str_trim()
  }
}

#------------------------------------------------------------------------------
# get_links_after_voting_estimates() ▸ Some "Voting intention" tables are not on
# the main page but on subpages linked immediately after an h5 header via a
# *hatnote*. This function collects those links together with the year they
# belong to.
#------------------------------------------------------------------------------

get_links_after_voting_estimates <- function(url) {

  # Grab siblings exactly like before
  siblings <- url |>
    read_html() |>
    xml_find_first(".//div[h4[@id='Voting_intention_estimates']]") |>
    xml_find_all("following-sibling::*")

  # Stop at the first big header (div.mw-heading[234])
  boundary <- which(xml_name(siblings) == "div" &
                      str_detect(xml_attr(siblings, "class"), "mw-heading[234]"))

  if (length(boundary) > 0) {
    siblings <- siblings[1:(boundary[1] - 1)]
  }

  links_with_years <- list()
  current_year <- NULL
  last_h5_id <- NULL

  for (i in seq_along(siblings)) {
    node <- siblings[[i]]

    # Detect the h5 headings to update current_year (same logic as before)
    if (xml_name(node) == "div" &&
        str_detect(xml_attr(node, "class"), "mw-heading5")) {

      # extract the year
      h5_id <- node |>
        xml_find_first(".//h5") |>
        xml_attr("id")

      current_year <- case_when(
        str_detect(h5_id, "^\\d{4}$") ~ as.numeric(h5_id), # 4 digits
        str_detect(h5_id, "^\\d{4}_") ~ as.numeric(str_extract(h5_id, "^\\d{4}")), # parenthesis
        str_detect(h5_id, "^\\d{4}–\\d{4}$") ~ as.numeric(str_extract(h5_id, "^\\d{4}")), # year range
        TRUE ~ as.numeric(str_extract(h5_id, "\\d{4}")) # anything else
      )

      last_h5_id <- h5_id

    }

    # Hatnote links appear right after the h5 header and live in <div class="hatnote">
    if (!is.null(current_year) && !is.na(current_year) &&
        xml_name(node) == "div" &&
        str_detect(xml_attr(node, "class"), "hatnote")) {

      link_node <- node |>
        xml_find_first(".//a[@href]")

      if (!is.na(link_node)) {
        full_url <- paste0("https://en.wikipedia.org",
                           xml_attr(link_node, "href"))

        links_with_years[[length(links_with_years) + 1]] <- list(
          url = full_url,
          year = current_year,
          id = last_h5_id
        )

      }
    }
  }

  # Name every link with its id or year
  names(links_with_years) <- map_chr(links_with_years, function(x) {
    if (!is.null(x$id)) x$id else as.character(x$year)
  })

  return(links_with_years)
}


#------------------------------------------------------------------------------
# get_tables_from_links() ▸ Drill into the subpages collected above, harvesting
# their wikitable(s) and tagging them with the correct year.
#------------------------------------------------------------------------------

get_tables_from_links <- function(url) {

  sub_links <- get_links_after_voting_estimates(url)

  if (length(sub_links) == 0) return(list())

  all_tables_from_links <- list()

  for (i in seq_along(sub_links)) {
    link_info <- sub_links[[i]]
    link_url <- link_info$url
    link_year <- link_info$year

    cat(sprintf("\n Processing link for subpage %s\n", link_year))

    # Fetch <div class="mw-heading3"> + each wikitable in the page
    tryCatch({
      siblings <- link_url |>
        read_html() |>
        xml_find_all("//div[h3] | //table[contains(@class, 'wikitable')]")

      last_h3_id <- NULL
      current_year <- link_year  # start with the year inferred from the parent link

      for (j in seq_along(siblings)) {
        node <- siblings[[j]]

        # if we find an h3 header, update current year
        if (xml_name(node) == "div" &&
            str_detect(xml_attr(node, "class"), "mw-heading3")) {

          h3_id <- node |>
            xml_find_first(".//h3") |>
            xml_attr("id")

          # Update current_year when encountering h3 tracks
          extracted_year <- case_when(
            str_detect(h3_id, "^\\d{4}$") ~ as.numeric(h3_id),
            str_detect(h3_id, "^\\d{4}_") ~ as.numeric(str_extract(h3_id, "^\\d{4}")),
            str_detect(h3_id, "^\\d{4}–\\d{4}$") ~ as.numeric(str_extract(h3_id, "^\\d{4}")),
            TRUE ~ as.numeric(str_extract(h3_id, "\\d{4}"))
          )

          current_year <- if (!is.na(extracted_year)) extracted_year else link_year
          last_h3_id <- h3_id

        }

        # If it's a wikitable, add it alongside its year and id
        if (xml_name(node) == "table" &&
            str_detect(xml_attr(node, "class"), "wikitable")) {

          # test if table can be parsed
          table_data <- tryCatch(html_table(node), error = function(e) NULL)

          if (!is.null(table_data) && nrow(table_data) > 1 && !is.null(current_year)) {

            all_tables_from_links[[length(all_tables_from_links) + 1]] <- list(
              table = node,
              year = current_year,
              id = last_h3_id
            )

            if (!is.null(last_h3_id)) {
              cat(sprintf("\t️Found h3 with ID: '%s' -> Year: %s\n", last_h3_id, current_year))
            }

            cat(sprintf("\tFound table in link with ID: '%s' -> Year: %s\n", h3_id, current_year))

          }
        }
      }
    })

  }

  # Name each list element after its year
  names(all_tables_from_links) <- map_chr(all_tables_from_links, ~ as.character(.x$year))

  return(all_tables_from_links)
}

#------------------------------------------------------------------------------
# extract_polling_data() ▸ Main orchestrator for one election year URL.
# 1) Download + parse all tables directly under "Voting intention estimates".
# 2) Detect any sub‑links and parse their tables too.
# 3) Harmonise the column names (polling firm, dates, sample, turnout, parties).
# 4) Return a *list of data frames* (one per table) still un‑cleaned.
#------------------------------------------------------------------------------

extract_polling_data <- function(url, election_year, election_type = NULL) {

  cat(sprintf("Starting extraction for %s (url: %s)\n\n", election_year, url))

  # Collect tables from main page and sub‑pages
  tables_main <- get_tables_after_voting_estimates(url)
  tables_links <- get_tables_from_links(url)

  all_tables_by_year <- c(tables_main, tables_links) |>  (\(x) split(x, names(x)))()
  all_tables <- flatten(all_tables_by_year)

  cat(sprintf("\nFound %d tables total (%d from main page, %d from links)\n",
              length(all_tables), length(tables_main), length(tables_links)))

  # Get party vectors per table, then convert xml tables to data frames
  all_parties <- get_all_parties(all_tables)

  # convert xml tables to data frames
  tables_list <- map(all_tables, function(x) html_table(x$table))
  table_years <- map_dbl(all_tables, function(x) {as.numeric(x$year)})
  table_ids <- map_chr(all_tables, function(x) {x$id %||% NA_character_})

  # Rename columns consistently. We leave deeper cleaning to clean_rows().
  clean_data <- map2(tables_list, seq_along(tables_list), function(data, table_index) {

    original_id <- table_ids[[table_index]]
    year <- table_years[[table_index]]
    cat(sprintf("\t Processing table %d: %s (year: %s)\n", table_index, original_id, year))

    # party names for this specific table
    raw_party_names <- all_parties[[table_index]]

    party_names <- raw_party_names

    colnames(data) <- c("polling_firm", "fieldwork_date", "sample_size", "turnout", party_names, "Lead")

    return(data)
  })

  cat(sprintf("\nCompleted extraction for %s\n", url))

  names(clean_data) <- table_ids

  return(clean_data)

}

#------------------------------------------------------------------------------
# clean_rows()  Heavy cleaner that:
#   1) Drops blank or meta rows
#   2) Splits fieldwork_date into fieldwork_start, fieldwork_end, n_field_days
#   3) Removes footnote refs, converts to numeric, truncates decimals
#   4) Adds polling‑firm / media split and optional electoral_year fallback
#------------------------------------------------------------------------------

clean_rows <- function(df, electoral_year = NULL) {

  last_col <- ncol(df)

  # Identify party columns (everything to the right of "turnout")
  cols <- names(df)[(match("turnout", names(df)) + 1):last_col] # The parties go after the turnout column

  # election type patterns to filter out! => only found these in the wikis!
  election_patterns <- c("general election", "local election", "EP election")

  df <- df |>
    filter(!if_all(all_of(cols), function(x) {is.na(x) | x == ""})) |> # remove fully empty rows
    slice(-1) |> # drop the 1st meta row
    # rows that contain election type strings in the first column (polling firm!!)
    filter(!str_detect(tolower(polling_firm), paste(election_patterns, collapse = "|"))) |>

    mutate(across(
      everything(),
      function(x) {case_when(
        x %in% c("–", "", "?", "—") ~ NA, # unify wiki placeholders
        str_starts(x, fixed("?")) ~ NA,
        TRUE ~ x
      )}
    )) |>
    mutate(across((match("turnout", names(df)) + 1):last_col, function(x) {str_extract(as.character(x), "\\d+\\.\\d+|\\d+")}))

  # Split “polling_firm / media” if both are in one cell
  df <- df |>
    mutate(
      polling_firm = str_remove_all(polling_firm, "\\[.*?\\]"), # strip footnote [1]
      polling_firm = str_trim(polling_firm),
      media = str_extract(polling_firm, "(?<=/)\\s*[^/]+$"),  # anything after last slash belongs to media
      polling_firm = str_extract(polling_firm, "^[^/]+") # left part is polling firm
    ) |>
    relocate(media, .after = polling_firm)

  df <- df |>
    mutate(sample_size = str_replace_all(sample_size, ",", ""))

  # Parse dates: fieldwork_start / fieldwork_end (two branches: with year in any oservation of the column or without)
  has_year <- any(str_detect(df$fieldwork_date, "[0-9]{4}"))

  if (has_year) { # Dates already include the year
    default_year <- str_extract(df$fieldwork_date, "[0-9]{4}") |> na.omit() |> as.numeric()

    df <- df |>
      mutate(
        start_day = str_extract(fieldwork_date, "^[0-9]{1,2}") |> as.numeric(),
        end_str = str_extract(fieldwork_date, "(?<=–)[0-9]{1,2}\\s*[A-Za-z]{3}\\s*[0-9]{4}|(?<=–)[0-9]{1,2}\\s*[A-Za-z]{3}") |>
          coalesce(str_extract(fieldwork_date, "[0-9]{1,2}\\s*[A-Za-z]{3}\\s*[0-9]{4}|[0-9]{1,2}\\s*[A-Za-z]{3}")),
        end_day = str_extract(end_str, "^[0-9]{1,2}") |> as.numeric(),
        end_day = if_else(is.na(end_day), start_day, end_day),
        start_month = str_extract(fieldwork_date, "^[0-9]{1,2}\\s*([A-Za-z]{3})") |> str_extract("[A-Za-z]{3}"),
        end_month = str_extract(end_str, "[A-Za-z]{3}"),
        start_month = if_else(is.na(start_month), end_month, start_month),
        end_month = if_else(is.na(end_month), start_month, end_month),
        year = str_extract(end_str, "[0-9]{4}") |> as.numeric(),
        year = if_else(is.na(year), default_year, year),

        # new vars
        fieldwork_start = sprintf("%02d.%02d.%d", start_day, match(start_month, month.abb), year),
        fieldwork_end = sprintf("%02d.%02d.%d", end_day, match(end_month, month.abb), year)
      )  |>
      select(-c(turnout, fieldwork_date, start_day, end_str, end_day, start_month, end_month, year))

  } else { # Year missing → use provided electoral_year or infer from polling_firm

    # fallback: using the passed electoral_year parameter from h5 header
    if (is.null(electoral_year) || is.na(electoral_year)) {

      extracted_year <- df$polling_firm[1] |>
        str_extract("[0-9]{4}") |>
        as.numeric()

      if (!is.na(extracted_year)) {
        electoral_year <- extracted_year
        cat(sprintf("Using year from polling_firm: %d\n", electoral_year))
      } else {
        stop("No electoral_year provided, no year found in dates, and no year found in polling_firm")
      }

    }

    df <- df |>
      mutate(

        # full range two months, ex.: 29 Jun–17 Jul
        full_str = str_extract(fieldwork_date, "([0-9]{1,2})\\s*([A-Za-z]{3})\\s*–\\s*([0-9]{1,2})\\s*([A-Za-z]{3})"),
        # fallback one month two dates, ex.: for 29–31 Jul (no month on start)
        end_str = coalesce(full_str, fieldwork_date),

        # extract start and end parts
        start_day = as.numeric(str_extract(end_str, "^[0-9]{1,2}")),
        start_month = str_extract(end_str, "^[0-9]{1,2}\\s*([A-Za-z]{3})") |> str_extract("[A-Za-z]{3}"),
        end_day = as.numeric(str_extract(end_str, "(?<=–)\\s*[0-9]{1,2}") |> str_trim()),
        end_month = str_extract(end_str, "[A-Za-z]{3}$"),

        # fallbacks
        start_month = if_else(is.na(start_month), end_month, start_month),
        end_day = if_else(is.na(end_day), start_day, end_day),
        end_month = if_else(is.na(end_month), start_month, end_month),

        # new vars
        fieldwork_start = sprintf("%02d.%02d.%d", start_day, match(start_month, month.abb), electoral_year),
        fieldwork_end = sprintf("%02d.%02d.%d", end_day, match(end_month, month.abb), electoral_year)

      ) |>
      select(-c(turnout, fieldwork_date, full_str, end_str, start_day, end_day, start_month, end_month))


  }

  # Remove old cols & reorder and convert to proper types

  df <- df |>
    relocate(c(fieldwork_start, fieldwork_end), .after = media) |>

    mutate(
      fieldwork_start = as.Date(fieldwork_start, format = "%d.%m.%Y"),
      fieldwork_end = as.Date(fieldwork_end, format = "%d.%m.%Y")
    ) |>
    mutate(
      fieldwork_start = if_else(
        fieldwork_start > fieldwork_end,
        fieldwork_start - years(1),
        fieldwork_start
      )
    ) |>

    mutate(
      n_field_days = as.integer(fieldwork_end - fieldwork_start + 1)
    ) |>
    relocate(n_field_days, .after = fieldwork_end) |>

    mutate(across(
      -c(polling_firm, media, fieldwork_start, fieldwork_end),
      function(x){as.numeric(x)}
    ))

  # Truncate (not round) values to 1 decimal, excluding sample_size

  numeric_cols <- names(df)[sapply(df, is.numeric)]
  cols_to_truncate <- setdiff(numeric_cols, "sample_size")

  for (col in cols_to_truncate) {
    df[[col]] <- trunc(df[[col]] * 10) / 10
  }

  return(df)

}

# Generating the database----------------------------------
url <- "https://en.wikipedia.org/wiki/Opinion_polling_for_the_next_Spanish_general_election"

new_polling_data <- extract_polling_data(url, "Next elections")

# The list names are the table years (as strings) – convert to numeric
years <- as.numeric(names(new_polling_data))

# Clean each table using the heavy 'clean_rows()' routine
clean_new_polling_data <- map2(new_polling_data, years, clean_rows)

new_polling_data <- bind_rows(clean_new_polling_data)

# Pivot to long format and harmonise party names
party_cols <- names(new_polling_data)[ (match("sample_size", names(new_polling_data)) + 1) : ncol(new_polling_data) ]

party_cols <- setdiff(party_cols, "Lead")

new_polling_data <- new_polling_data |>
  pivot_longer(cols = all_of(party_cols), names_to = "abbrev_candidacies", values_to = "estimated_seats") |>
  drop_na(estimated_seats)

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

# ----- UTF-8 -----

new_polling_data <-
  new_polling_data |>
  mutate(across(where(is.character), \(x) enc2utf8(x)))

if (!file.exists("data/next_election_polling_data.rda")){

  next_election_polling_data <- new_polling_data

  usethis::use_data(next_election_polling_data, overwrite = TRUE,
                    compress = "xz")

} else if (nrow(new_polling_data) > nrow(next_election_polling_data)) {

  next_election_polling_data <- new_polling_data


  usethis::use_data(next_election_polling_data, overwrite = TRUE,
                    compress = "xz")

}
