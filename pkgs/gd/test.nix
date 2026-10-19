# gd against a local directory standing in for Drive (an rclone alias remote defined by env).
{ pkgs, gd }:
pkgs.runCommand "gd-check" { nativeBuildInputs = [ gd ]; } ''
  export HOME=$TMPDIR/home GD_REMOTE=fake RCLONE_CONFIG_FAKE_TYPE=alias RCLONE_CONFIG_FAKE_REMOTE=$TMPDIR/drive
  export GD_SYNC_LOCAL=$TMPDIR/sync GD_SYNC_REMOTE=mirror GD_BACKUP_DIR=$TMPDIR/backup
  mkdir -p $HOME $TMPDIR/drive $TMPDIR/work/proj/sub && cd $TMPDIR/work
  echo hello >a.txt && echo deep >proj/sub/b.txt

  gd push a.txt
  gd push a.txt proj inbox/
  test "$(cat $TMPDIR/drive/a.txt)" = hello
  test -f $TMPDIR/drive/inbox/a.txt && test -f $TMPDIR/drive/inbox/proj/sub/b.txt
  gd ls inbox | grep -qx 'proj/'
  gd find 'b.TXT' | grep -qx 'inbox/proj/sub/b.txt'

  mkdir out && gd pull inbox/proj inbox/a.txt out
  test "$(cat out/proj/sub/b.txt)" = deep && test -f out/a.txt
  echo piped | gd put notes/p.txt && test "$(gd cat notes/p.txt)" = piped
  gd mv notes/p.txt notes/q.txt && test -f $TMPDIR/drive/notes/q.txt
  gd rm notes/q.txt && test ! -e $TMPDIR/drive/notes/q.txt
  echo y | gd rm inbox && test ! -e $TMPDIR/drive/inbox

  # sync down keeps what it would delete under the backup dir.
  mkdir -p $GD_SYNC_LOCAL && echo local >$GD_SYNC_LOCAL/only-local.txt
  echo y | gd sync up && test -f $TMPDIR/drive/mirror/only-local.txt
  rm $TMPDIR/drive/mirror/only-local.txt && echo remote >$TMPDIR/drive/mirror/r.txt
  echo y | gd sync down
  test -f $GD_SYNC_LOCAL/r.txt && test ! -e $GD_SYNC_LOCAL/only-local.txt
  find $GD_BACKUP_DIR -name only-local.txt | grep -q .

  gd bisync --resync && echo two-way >$GD_SYNC_LOCAL/t.txt && gd bisync
  test -f $TMPDIR/drive/mirror/t.txt

  mkdir picked && cd picked && FZF_DEFAULT_OPTS=--filter=r.txt gd pick mirror && test -f r.txt && cd ..

  if GD_REMOTE=missing gd ls 2>err; then exit 1; fi
  grep -q 'gd setup' err
  touch $out
''
