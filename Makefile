.PHONY: test

TEST_SOURCES = $(wildcard test/integration/*_test.rbs)
TEST_OUTPUTS = $(patsubst test/integration/%.rbs, tmp/integration/%.js, $(TEST_SOURCES))

tmp/integration/%.js: test/integration/%.rbs
	@mkdir -p tmp/integration
	bin/rbs compile $< -o $@

test: $(TEST_OUTPUTS)
	node_modules/.bin/mocha --ui tdd \
		test/integration/test_helper.js tmp/integration/*_test.js

clean:
	rm -rf tmp/integration/*_test.js
