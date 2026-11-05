---
name: release
description: Publish fin's current main to the public GitHub repo (fogapp/fin) as a single commit, without the private git history.
disable-model-invocation: true
---

# Release: publish to public GitHub

Fin's private history lives on gitea.lan. This publishes main's tree to
`github.com/fogapp/fin` as one commit: `Initial public release` the first
time, `Sync YYYY-MM-DD` after that. Private commits, subjects and authors stay
private.

All of the mechanics live in `bin/publish-public`. Never run `commit-tree` or
`git push` to the public repo by hand: a raw push of `main` uploads the entire
history, and that can't be taken back.

## 0. Preconditions

- This clone names the public identity the commit is made under — never the
  owner's personal git identity:

  ```
  git config --get fin.publicAuthorName
  git config --get fin.publicAuthorEmail
  ```

  If either is empty, **stop** and ask the user to choose and set them. Don't
  pick values yourself. The script refuses without them.
- `~/.ssh/fog_ed25519` (fogapp's key) exists; the script pushes with it.
- `github.com/fogapp/fin` exists. If the script says it can't reach it, the
  user creates it (empty, no README/license) while logged in as fogapp:
  `gh repo create fogapp/fin --public` after
  `gh auth switch --hostname github.com --user fogapp`. Don't create it
  unasked.

## 1. Dry run

```
bin/publish-public
```

This changes nothing on GitHub. If it stops, report why and don't work around it:

- **Dirty tree, untracked files, or main differs from origin:** tell the user;
  don't commit or push to fix it unasked.
- **`public/main` has commits this script didn't make:** someone changed the
  public repo. They need bringing into `main` first, or the sync erases them.
- **Secret scan hit:** go to step 2 before anything else.
- **"binary files over … that aren't images, fonts or icons":** tell the user
  which file; don't publish it and don't delete it.
- **"nothing to publish":** public already matches main; say so and stop.

## 2. Read what's going public

The scan only recognises common credential formats, so read the change too:

```
git diff --stat public/main HEAD
git diff public/main HEAD -- <anything that looks sensitive>
```

(On the first publish there's no `public/main`; review `git ls-files`.)

Look for credentials the scan can't recognise, personal or household financial
data (real balances, account numbers, names, CSV exports in `data/` or spec
fixtures), and new files never meant to be public. Existing `gitea.lan` and
`192.168.*` references are known; a new one that reveals something more isn't.

If anything is doubtful, stop and show the user the path and why, without
repeating a secret's value. Pass `--accept-findings` only once the user, or
your reading of the match, shows it's a false positive, and say which you
accepted.

## 3. Publish

```
bin/publish-public --push
```

Invoking `/release` is the user's go-ahead for this step, as long as step 2
was clean.

## 4. Report

Give the commit message and SHA the script printed, the file count from the
diff, and any accepted findings. Say it's published only if the script printed
`published "…" as <sha>`. If a secret reached GitHub, tell the user to rotate
it: a force-push doesn't undo the exposure.
