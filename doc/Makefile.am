dist_man_MANS = \
		rygel.1 \
		rygel.conf.5

EXTRA_DIST = \
		man/rygel.xml \
		man/rygel.conf.xml

if HAVE_XSLTPROC
%.5 %.1: man/%.xml
	$(XSLTPROC) -o $@ -nonet http://docbook.sourceforge.net/release/xsl/current/manpages/docbook.xsl $<
CLEANFILES = \
		$(dist_man_MANS)
endif
