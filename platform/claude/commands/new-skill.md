Create a new skill in `~/.claude/skills/<skill-name>/SKILL.md`.

1. Ask me: what's the trigger? What should it do?
2. Draft the skill using the standard format:
   - YAML frontmatter with `name` and `description` (description is what determines when you invoke it — be specific about triggers).
   - Self-update block (WebSearch for current best practices, propose updates).
   - Steps as a numbered list.
   - Checkpoints (stop and ask).
   - Related skills.
   - Last reviewed comment.
3. Show me the draft. Apply only with my approval.
4. After saving, suggest whether the global CLAUDE.md should reference this skill.
