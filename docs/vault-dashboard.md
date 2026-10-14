---
title: Vault Dashboard
tags:
  - moc
  - tooling
---

# Vault dashboard

Live views over `docs/`. They render in Obsidian with Dataview and Tasks
enabled; anywhere else this page reads as its queries. The same Dataview
queries can be sent by an agent to the Local REST API's `/search/` endpoint
(content type `application/vnd.olrapi.dataview.dql+txt`), so a session can
ask the vault a question without reading every file. See [[vault]].

## Open author calls

```tasks
not done
path includes docs/someday
group by filename
```

## Hygiene

Docs with no `title` in their frontmatter (should be empty; the
[[templates/model-doc|model-doc template]] writes one):

```dataview
LIST
FROM "docs"
WHERE !title AND !endswith(file.name, ".excalidraw") AND !contains(file.folder, "templates") AND !contains(file.folder, "superpowers")
```

Docs no other note links to (should be empty, or explained):

```dataview
LIST
FROM "docs"
WHERE length(file.inlinks) = 0 AND !contains(file.folder, "templates") AND !contains(file.folder, "superpowers")
```

## Models

```dataview
TABLE WITHOUT ID file.link AS "Model", length(file.inlinks) AS "Linked from", file.mtime AS "Last edited"
FROM "docs"
WHERE contains(tags, "model")
SORT file.mtime DESC
```

## Recently edited

```dataview
TABLE WITHOUT ID file.link AS "Doc", file.mtime AS "Edited"
FROM "docs"
SORT file.mtime DESC
LIMIT 12
```
