import os, osproc, strutils, terminal

const
  bannerRaw = staticRead("../assets/tbann")
  handle = "lowcache"
  onlineHandle = "@drawpdeadredd"
  
  # Colors
  red = "\e[1;31m"
  yellow = "\e[1;33m"
  cyan = "\e[1;36m"
  magenta = "\e[1;35m"
  white = "\e[1;37m"
  reset = "\e[0m"

  # Big Text: Infernal NixOS (Blocky style)
  titleArt = [
    "  ___ _   _ _____ _____ ____  _   _    _    _       ",
    " |_ _| \ | |  ___| ____|  _ \| \ | |  / \  | |      ",
    "  | ||  \| | |_  |  _| | |_) |  \| | / _ \ | |      ",
    "  | || |\  |  _| | |___|  _ <| |\  |/ ___ \| |___   ",
    " |___|_| \_|_|   |_____|_| \_\_| \_/_/   \_\_____|  ",
    "           _   _ _____  _____  ____                 ",
    "          | \ | |_ _\ \/ / _ \/ ___|                ",
    "          |  \| || | \  / | | \___ \                ",
    "          | |\  || | /  \ |_| |___) |               ",
    "          |_| \_|___/_/\_\___/|____/                "
  ]
  
  tagline = "neither master nor slave to neither god nor man. lowcache 2026"

proc stripAnsi(s: string): string =
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '\e':
      inc i
      if i < s.len and s[i] == '[':
        inc i
        while i < s.len and not (s[i] in {'a'..'z', 'A'..'Z'}):
          inc i
        inc i
    else:
      result.add s[i]
      inc i

proc centerText(text: string) =
  let width = terminalWidth()
  let cleanText = stripAnsi(text)
  let padding = (width - cleanText.len) div 2
  if padding > 0:
    stdout.write(repeat(' ', padding))
  stdout.writeLine(text)

proc getUptime(): string =
  try:
    let up = execProcess("uptime -p").strip()
    return up.replace("up ", "")
  except: return "unknown"

proc getOS(): string =
  try:
    for line in readFile("/etc/os-release").splitLines():
      if line.startsWith("NAME="):
        return line.split('=')[1].strip(chars = {'"'})
    return "NixOS"
  except: return "NixOS"

proc drawInfoTable() =
  let width = terminalWidth()
  let 
    k1 = "OS"
    v1 = getOS()
    k2 = "Kernel"
    v2 = execProcess("uname -r").strip()
    k3 = "Shell"
    v3 = os.getEnv("SHELL").lastPathPart()
    k4 = "Uptime"
    v4 = getUptime()

  # Formatting info into a table
  let tableWidth = 50
  let padding = (width - tableWidth) div 2
  let padStr = if padding > 0: repeat(' ', padding) else: ""

  let border = "┏" & repeat("━", tableWidth - 2) & "┓"
  let divider = "┠" & repeat("─", tableWidth - 2) & "┨"
  let bottom = "┗" & repeat("━", tableWidth - 2) & "┛"

  stdout.writeLine(padStr & white & border & reset)
  
  proc row(key, val: string) =
    let cleanLine = "  " & key & ": " & val
    let spaces = tableWidth - 4 - cleanLine.len
    stdout.writeLine(padStr & white & "┃" & reset & yellow & " " & key & reset & white & " ➜ " & reset & cyan & val & repeat(" ", if spaces > 0: spaces else: 0) & white & " ┃" & reset)

  row(k1, v1)
  row(k2, v2)
  row(k3, v3)
  row(k4, v4)
  
  stdout.writeLine(padStr & white & bottom & reset)

proc main() =
  # Clear and Prepare
  stdout.write("\e[H\e[2J")
  
  let lines = bannerRaw.splitLines()
  let mid = lines.len div 2
  let termWidth = terminalWidth()

  # 1. Print first half of tbann
  for i in 0 ..< mid:
    let padding = (termWidth - 100) div 2 # Approx width
    if padding > 0: stdout.write(repeat(' ', padding))
    stdout.writeLine(lines[i])

  stdout.writeLine("")

  # 2. Print Big Title
  for line in titleArt:
    centerText(red & line & reset)
  
  stdout.writeLine("")
  centerText(magenta & tagline & reset)
  stdout.writeLine("")

  # 3. Print second half of tbann
  for i in mid ..< lines.len:
    let padding = (termWidth - 100) div 2
    if padding > 0: stdout.write(repeat(' ', padding))
    stdout.writeLine(lines[i])

  stdout.writeLine("")

  # 4. Branding & Table
  centerText(yellow & handle & reset & " ➜ " & cyan & onlineHandle & reset)
  stdout.writeLine("")
  drawInfoTable()
  stdout.writeLine("")

when isMainModule:
  main()
