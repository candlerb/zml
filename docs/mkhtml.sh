#!/bin/sh

SP_CHARSET_FIXED="YES"; export SP_CHARSET_FIXED
SP_ENCODING="XML"; export SP_ENCODING
SGML_CATALOG_FILES="/usr/local/share/xml/jade/xml.soc"; export SGML_CATALOG_FILES

SGML_BASE_DIR="/usr/local/share/sgml"; export SGML_BASE_DIR
SGML_CATALOGS_DIR="/usr/local/share/sgml"; export SGML_CATALOGS_DIR

cd html
jade -t sgml \
 -i html \
 -d /usr/local/share/sgml/docbook/utils-0.6.14/docbook-utils.dsl#html \
 -V paper-type=A4 \
 -w xml \
 /usr/local/share/xml/jade/xml.dcl \
 ../zimmel.dbk
