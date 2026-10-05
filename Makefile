PYTHON ?= python3

.PHONY: check lint test reproduce

check: lint test
	$(PYTHON) scripts/analyze.py --check

lint:
	$(PYTHON) -m black --check scripts tests
	$(PYTHON) -m isort --check-only scripts tests
	$(PYTHON) -m flake8 scripts tests

test:
	$(PYTHON) -m pytest

reproduce:
	$(PYTHON) scripts/analyze.py --update-readme
