Explain what this jq filter does in 4 sentences or fewer:

```jq
select(.tool == "Bash" and (.class // "") == "git")
| [.session_id, .ts]
| @tsv
```

Your answer must mention what rows are selected and what fields are emitted.
