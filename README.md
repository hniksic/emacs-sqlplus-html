# sqlplus-html

**Note that I no longer use Oracle, so this package might not work out
of the box.  If you try it, please drop me a note.**

This package processes the output of SQL\*Plus to format it into
nice-looking tables a la mysql's command line client.  This is
feasible thanks to the fact that SQL\*Plus has an option to produce
HTML output, and that links and w3 handle HTML tables nicely.

For the mode to work, you will need a working `w3` package or the
`links` external text-based browser.  Start the `sqlplus` client in a
comint (i.e. shell) buffer.  Then execute `M-x sqlplus-html-init-all`,
and you should be set.

To test whether this works as intended, issue a simple query such
as `select 2+2 from dual`.  The result should look like this:

```
SQL>select 2+2 from dual;

+---+
|2+2|
|---|
| 4 |
+---+
```

`sqlplus-html-init-all` does two things: sends "set markup html on" to
SQL\*Plus to make it write all output in HTML; and and puts the buffer
in `sqlplus-html` minor mode so that the HTML output is rendered on
the fly.

You can disable the mode at any time with `M-x sqlplus-html-mode`,
which works as a toggle.
