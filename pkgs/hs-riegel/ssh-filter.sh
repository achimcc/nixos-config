# hs-deploy-ssh-filter — laesst aus einer ssh_config nur Direktiven durch, die
# weder Code ausfuehren noch die Hostschluessel-Pruefung aufweichen koennen
# (Begruendung in hs-deploy.sh). stdin -> stdout.
# Exit 0: gefiltert (verworfene Direktiven stehen namentlich auf stderr).
# Exit 1: eine Match-Zeile mit einer Bedingung ausser host/user/all — sie
#         wegzulassen haengte die folgenden Zeilen an den vorigen Block.
awk '
BEGIN {
  split("host match hostname user port identityfile identitiesonly hostkeyalias", a, " ")
  for (i in a) erlaubt[a[i]] = 1
  split("host originalhost user localuser", b, " ")
  for (i in b) bedingung[b[i]] = 1
  fehler = 0
}
{
  zeile = $0
  sub(/^[ \t]+/, "", zeile)
  if (zeile == "" || substr(zeile, 1, 1) == "#") next
  # "Schluessel Wert" oder "Schluessel=Wert"
  schluessel = zeile
  sub(/[ \t=].*$/, "", schluessel)
  schluessel = tolower(schluessel)
  rest = substr(zeile, length(schluessel) + 1)
  sub(/^[ \t]*=?[ \t]*/, "", rest)
  if (!(schluessel in erlaubt)) {
    verworfen[schluessel] = 1
    next
  }
  if (schluessel == "match") {
    n = split(rest, t, /[ \t]+/)
    i = 1
    while (i <= n) {
      k = tolower(t[i]); sub(/^!/, "", k)
      if (k == "all") { i++; continue }
      if (!(k in bedingung) || i == n) { fehler = 1; break }
      i += 2
    }
  }
  print schluessel " " rest
}
END {
  for (k in verworfen) printf "hs-deploy: ssh_config: %s verworfen\n", k > "/dev/stderr"
  exit fehler
}'
