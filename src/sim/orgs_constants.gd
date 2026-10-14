extends RefCounted

## Content ids the sim addresses by name. Not a tuning file: orgs.gd's numbers live in
## data/orgs/*.json; this holds the one id that code outside orgs.gd has to spell.

## The Union is the one org the event book and the precondition readers address by
## name: `accession_won` is its accession, `eu_member` is membership in it.
## `Orgs.parliament(loader)` finds the org from content (it is the one with a
## parliament), but `Legislature.read_field` (which `Programme._read_field` delegates
## to) has no loader -- it reads a nation's `orgs` list and nothing else -- so the id
## has to be spelled somewhere. Once, here, rather than as a string literal at each reader: the
## day the Union's content id changes, one line moves and a grep finds no strays.
const UNION_ORG_ID := "eu"
