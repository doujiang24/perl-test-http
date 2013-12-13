.PHONY: test

test:
	prove -I ./lib -r t/
