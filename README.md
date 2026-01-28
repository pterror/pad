# pad

> [!NOTE]
> This is vibe coded with LLM assistance. Even if you'd rather not use the code directly, maybe the ideas will spark something for you!

the home for your thoughts

```bash
flow | pad
```

## what it does

Anything you pipe into pad becomes:
- structured
- linked
- saved
- searchable

No UI. No dashboard. No ceremony.

## quick start

```bash
# pipe anything in
echo "hello world" | pad

# capture command output
ls -la | pad

# search later
pad query "hello"
```

## how it works

```
stdin → pad → structure
```

pad captures what you give it, figures out its shape (list? log? url? text?), and stores it in a local graph. Everything links together. Nothing gets lost.

## extensions

pad lives wherever you work:

- **clipboard** - every copy becomes memory
- **shell** - `| pad` anywhere
- **browser** - pages become structure
- **git** - commits become context
- **vscode/vim** - code becomes thought

Extensions are thin adapters. Core does the real work.

## install

```bash
# clone
git clone https://github.com/user/pad ~/git/pad

# add to shell
echo 'source ~/git/pad/extensions/shell/pad.bash' >> ~/.bashrc
```

Requires: LuaJIT (bundled), SQLite (bundled on Windows, system on Linux)

## structure

```
core/           -- the heart
  pad.lua       -- entry point
  pad/          -- modules
  dep/          -- bundled deps

extensions/     -- integrations
  shell/
  clipboard/
  ...
```

## philosophy

pad is a membrane between human activity and persistent structure.

It doesn't help. It doesn't assist. It doesn't chat.

It just remembers.

