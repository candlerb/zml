# Build the documentation directory 'doc'

doc:
	rdoc lib/zml bin/zml_initdb bin/zml_restore bin/zml_dump

tgz:
	cd .. && tar -czf zml-`date +%Y%m%d`.tgz --exclude '*~' --exclude '*.db' \
	zml/Makefile zml/README* zml/bin zml/lib zml/test
