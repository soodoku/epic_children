.PHONY: restore analysis figures tables reproduce format lint test check ci-docker

restore:
	Rscript -e 'renv::restore(prompt = FALSE)'

analysis:
	Rscript scripts/run_all.R

figures: analysis
	Rscript scripts/figures.R

tables: analysis
	Rscript scripts/tables.R

reproduce: figures tables

format:
	Rscript -e 'styler::style_dir("R"); styler::style_dir("scripts"); styler::style_dir("tests")'

lint:
	Rscript -e 'l <- unlist(lapply(c("R", "scripts", "tests"), lintr::lint_dir), recursive = FALSE); print(l); quit(status = as.integer(length(l) > 0))'

test:
	Rscript -e 'testthat::test_dir("tests/testthat", stop_on_failure = TRUE)'

check: lint test
	Rscript scripts/run_all.R --check

ci-docker:
	docker run --rm -v "$(PWD):/project" -w /project rocker/r-ver:4.6.0 \
		bash -lc "apt-get update && apt-get install -y --no-install-recommends libcurl4-openssl-dev libssl-dev libxml2-dev && Rscript -e 'install.packages(\"renv\", repos = \"https://cloud.r-project.org\")' && make restore check"
