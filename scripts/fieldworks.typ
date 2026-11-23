// Fieldworks spec PDF theme. scripts/build-pdf.sh passes this file to pandoc
// as the Typst template; pandoc calls conf() with the document metadata.
//
// Palette matches the Pages edition: purple for chapter titles and callouts,
// teal for section headings, tables, code bars and rules.

#let ink = rgb("#1d2731")
#let purple = rgb("#A1449F")
#let teal = rgb("#00A0B0")
#let muted = rgb("#5b6b7a")
#let rule-color = rgb("#d5dde5")
#let code-bg = rgb("#f3f6f9")
#let stripe = rgb("#F1F4F5")
#let callout-bg = rgb("#F3EAF5")

#let sans = ("IBM Plex Sans",)
#let mono = ("IBM Plex Mono",)

#let content-to-string(content) = {
  if content == none { "" }
  else if type(content) == str { content }
  else if content.has("text") { content.text }
  else if content.has("children") { content.children.map(content-to-string).join("") }
  else if content.has("body") { content-to-string(content.body) }
  else if content == [ ] { " " }
  else { "" }
}

// "Part III - The Agent Layer" -> ("Part III", "The Agent Layer"); else none.
#let split-part(title) = {
  let m = content-to-string(title).match(regex("^(Part [IVXLC]+)\s+[-–—]\s+(.+)$"))
  if m == none { none } else { m.captures }
}

#let cover(title, subtitle, authors, date) = page(header: none, footer: none)[
  // "FieldWorks Framework Specification": the name in purple, the rest below.
  #let words = content-to-string(title).split(" ")
  #v(2.2in)
  #text(size: 10.5pt, weight: "semibold", fill: muted, tracking: 0.2em)[
    OPEN SOURCE INDUSTRIAL AI FRAMEWORK
  ]
  #v(0.2em)
  #text(size: 40pt, weight: "bold", fill: purple, hyphenate: false)[#words.first()]
  #v(-0.9em)
  #text(size: 30pt, weight: "bold", fill: black, hyphenate: false)[#words.slice(1).join(" ")]
  #v(0.1em)
  #line(length: 2.2in, stroke: 3pt + teal)
  #v(0.6em)
  #if subtitle != none {
    text(size: 15pt, weight: "medium", fill: muted)[#subtitle]
  }
  #place(bottom + left)[
    #set text(fill: muted, size: 10.5pt)
    #for author in authors [#author.name \ ]
    #if date != none [#date]
  ]
]

#let conf(
  title: none,
  subtitle: none,
  authors: (),
  keywords: (),
  date: none,
  abstract-title: none,
  abstract: none,
  thanks: none,
  cols: 1,
  margin: (x: 1in, top: 1.1in, bottom: 1in),
  paper: "us-letter",
  lang: "en",
  region: "US",
  font: none,
  fontsize: 10pt,
  mathfont: none,
  codefont: none,
  linestretch: 1,
  sectionnumbering: none,
  linkcolor: none,
  citecolor: none,
  filecolor: none,
  pagenumbering: "1",
  doc,
) = {
  set document(title: title, keywords: keywords)
  set document(
    author: authors.map(a => content-to-string(a.name)).join(", ", last: " & "),
  ) if authors != none and authors != ()

  set text(font: sans, size: fontsize, fill: ink, lang: lang, region: region)
  set par(justify: false, leading: 0.72em, spacing: 1.1em)
  set list(indent: 0.6em, marker: text(fill: teal)[•])
  set enum(indent: 0.6em)

  // ── Cover ────────────────────────────────────────────────────────────────
  cover(title, subtitle, authors, date)

  // ── Pages ────────────────────────────────────────────────────────────────
  let title-text = content-to-string(title)
  let version-text = content-to-string(subtitle)
  set page(
    paper: paper,
    margin: margin,
    header: context {
      let here-page = here().page()
      // No header on a page that opens a chapter.
      let opens = query(heading.where(level: 1)).any(h => h.location().page() == here-page)
      if opens { return }
      let before = query(heading.where(level: 1).before(here()))
      let chapter = if before.len() > 0 {
        let parts = split-part(before.last().body)
        if parts == none { before.last().body } else [#parts.at(0) · #parts.at(1)]
      }
      set text(size: 8pt, fill: muted)
      grid(
        columns: (1fr, auto),
        [#title-text #h(0.4em) #text(fill: teal)[|] #h(0.4em) #version-text],
        chapter,
      )
      v(-0.5em)
      line(length: 100%, stroke: 0.5pt + rule-color)
    },
    footer: context {
      set text(size: 8.5pt, fill: muted)
      align(right)[#counter(page).display("1")]
    },
  )
  counter(page).update(1)

  // ── Headings ─────────────────────────────────────────────────────────────
  set heading(numbering: sectionnumbering)
  show heading: set text(fill: teal, hyphenate: false)
  show heading: set block(sticky: true)

  // Every top-level heading opens a page: each Part, and each section of
  // the Introduction.
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    let parts = split-part(it.body)
    block(width: 100%, above: 0pt, below: 1.6em)[
      #v(0.6in)
      #if parts != none {
        text(size: 11pt, weight: "semibold", fill: teal, tracking: 0.2em)[
          #upper(parts.at(0))
        ]
        v(0.1em)
        text(size: 26pt, weight: "bold", fill: purple)[#parts.at(1)]
      } else {
        text(size: 24pt, weight: "bold", fill: purple)[#it.body]
      }
      #v(-0.3em)
      #line(length: 1.4in, stroke: 3pt + teal)
    ]
  }
  show heading.where(level: 2): it => block(above: 2em, below: 0.9em, width: 100%)[
    #text(size: 15pt, weight: "semibold")[#it.body]
    #v(-0.55em)
    #line(length: 100%, stroke: 0.75pt + rule-color)
  ]
  show heading.where(level: 3): it => block(above: 1.6em, below: 0.7em)[
    #text(size: 12pt, weight: "semibold")[#it.body]
  ]
  show heading.where(level: 4): it => block(above: 1.3em, below: 0.6em)[
    #text(size: 10.5pt, weight: "semibold", fill: ink)[#it.body]
  ]

  // ── Contents ─────────────────────────────────────────────────────────────
  show outline.entry.where(level: 1): it => {
    v(0.9em, weak: true)
    text(weight: "semibold", fill: purple)[#it]
  }
  set outline.entry(fill: text(fill: rule-color)[#repeat[.#h(0.3em)]])

  // ── Links ────────────────────────────────────────────────────────────────
  show link: set text(fill: teal)
  show link: it => if type(it.dest) == str { underline(stroke: 0.5pt + teal.lighten(50%), offset: 2pt, it) } else { it }

  // ── Code ─────────────────────────────────────────────────────────────────
  show raw: set text(font: mono, size: 0.92em)
  show raw.where(block: false): it => box(
    fill: code-bg,
    inset: (x: 2.5pt),
    outset: (y: 2.5pt),
    radius: 2pt,
    text(fill: ink, it),
  )
  show raw.where(block: true): it => block(
    width: 100%,
    fill: code-bg,
    inset: (x: 10pt, y: 9pt),
    radius: 3pt,
    stroke: (left: 2.5pt + teal),
    breakable: true,
    text(size: 8.5pt, it),
  )

  // ── Callouts (Markdown blockquotes) ──────────────────────────────────────
  show quote.where(block: true): it => block(
    width: 100%,
    fill: callout-bg,
    inset: (x: 12pt, y: 10pt),
    radius: (right: 3pt),
    stroke: (left: 3pt + purple),
    breakable: true,
    text(fill: purple, it.body),
  )

  // ── Tables ───────────────────────────────────────────────────────────────
  set table(
    inset: (x: 7pt, y: 6pt),
    stroke: (x, y) => (bottom: 0.5pt + rule-color),
    fill: (x, y) => if y == 0 { teal } else if calc.even(y) { stripe } else { white },
  )
  show table.cell.where(y: 0): set text(fill: white, weight: "semibold", size: 9pt)
  show table: set text(size: 9pt)
  show table.cell.where(y: 0): it => {
    show raw: r => text(fill: white, r.text)
    it
  }
  show figure.where(kind: table): set block(above: 1.4em, below: 1.4em)
  show figure.where(kind: table): set align(left)

  // ── Figures ──────────────────────────────────────────────────────────────
  show figure.caption: set text(size: 8.5pt, fill: muted, style: "italic")

  doc
}
