#!/usr/bin/env python3
"""Télécharge des dictionnaires FreeDict (TEI) et produit dicts/<paire>.tsv : clé<TAB>mot<TAB>définition.
Usage : python3 -I tools/build_dicts.py <dossier de travail>"""
import sys, os, json, urllib.request, tarfile, unicodedata, xml.etree.ElementTree as ET
work = sys.argv[1]; out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dicts")
PAIRS = ["fra-eng","eng-fra","spa-eng","eng-spa","ita-eng","eng-ita","por-eng","eng-por","nld-eng","eng-nld","jpn-eng","eng-jpn"]
db = {e["name"]: e for e in json.load(urllib.request.urlopen("https://freedict.org/freedict-database.json")) if e.get("name")}
ns = {"t": "http://www.tei-c.org/ns/1.0"}
def key(s):
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")
for p in PAIRS:
    url = [r["URL"] for r in db[p]["releases"] if r["platform"] == "src"][0]
    d = os.path.join(work, p); os.makedirs(d, exist_ok=True)
    f = os.path.join(d, "src.tar.xz")
    if not os.path.exists(f): urllib.request.urlretrieve(url, f)
    with tarfile.open(f) as t:
        m = [x for x in t.getmembers() if x.name.endswith(".tei")][0]
        t.extract(m, d, filter="data"); tei = os.path.join(d, m.name)
    entries = {}
    for e in ET.parse(tei).getroot().iter("{%s}entry" % ns["t"]):
        orth = e.find("t:form/t:orth", ns)
        if orth is None or not (orth.text or "").strip(): continue
        w = base = orth.text.strip()
        pr = e.find("t:form/t:pron", ns)
        if pr is not None and pr.text: w += " (%s)" % pr.text.strip()
        pos = e.find("t:gramGrp/t:pos", ns)
        tr = []
        for q in e.iterfind(".//t:cit[@type='trans']/t:quote", ns):
            if q.text and q.text.strip() and q.text.strip() not in tr: tr.append(q.text.strip())
        if not tr: continue
        line = ("(%s) " % pos.text.strip() if pos is not None and pos.text else "") + "; ".join(tr)
        entries.setdefault((base, w), []).append(line)
    rows = sorted(((key(b), w, "¶".join(v)) for (b, w), v in entries.items()), key=lambda r: (r[0], r[1]))
    with open(os.path.join(out, p + ".tsv"), "w", encoding="utf-8") as o:
        for k, w, v in rows: o.write("%s\t%s\t%s\n" % (k.replace("\t", " "), w.replace("\t", " "), v.replace("\t", " ").replace("\n", " ")))
    print(p, len(rows))
