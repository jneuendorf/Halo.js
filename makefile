make:
	cat Halo.coffee | coffee --compile --stdio > Halo.js

# test:
# 	cat data_example.json JQL.coffee Schema.coffee Table.coffee linking.coffee Test.coffee | coffee --compile --stdio > JQL.js

production: make
	uglifyjs Halo.js -o Halo.min.js --compress --mangle drop_console=true -d DEBUG=false
