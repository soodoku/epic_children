script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
root <- dirname(dirname(normalizePath(script)))
setwd(root)
if (Sys.getenv("RENV_PROJECT") != root) source("renv/activate.R")
for (file in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(file)

args <- commandArgs(trailingOnly = TRUE)
if (identical(args, "--check")) {
  repository <- load_repository()
  cat(sprintf(
    "Validated %d records and %d alternative codings.\n",
    nrow(repository$children) + nrow(repository$prayers), length(repository$alternatives)
  ))
} else {
  output <- "results"
  if (length(args)) {
    if (length(args) != 2L || args[1] != "--output-dir") {
      stop("Usage: Rscript scripts/run_all.R [--check | --output-dir PATH]")
    }
    output <- args[2]
  }
  generate_results(output = output)
  cat("Wrote descriptive results to", normalizePath(output), "\n")
}
