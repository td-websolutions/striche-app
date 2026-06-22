# Striche – Marketing-Website

Statische Landingpage für die Getränkelisten-App **Striche**. Kein Build-Step,
keine Abhängigkeiten – reines HTML/CSS/JS. Läuft lokal und auf jedem Static-Host.

## Lokal ansehen

```bash
cd website
python3 -m http.server 8000
# -> http://localhost:8000
```

Oder einfach `index.html` im Browser öffnen.

## Dateien

| Datei | Zweck |
|-------|-------|
| `index.html` | Seiteninhalt + SEO-Meta + strukturierte Daten (SoftwareApplication, FAQPage) |
| `styles.css` | Design – spiegelt exakt die App-Palette (`Theme.swift`) |
| `app.js` | Interaktive Phone-Demo (Getränke buchen, Liquid-Fill, +1, Konfetti) + Scroll-Reveals |
| `assets/favicon.svg` | Favicon (Bierkrug + Strichliste) |
| `assets/og-image.png` | Social-Preview 1200×630 (WhatsApp/Facebook/Twitter) |
| `robots.txt`, `sitemap.xml` | SEO / Crawling |

## SEO

- Ziel-Keywords: *Getränkeliste Verein(e)*, *digitale Strichliste*, *Getränkewart App*,
  *Getränkeabrechnung Verein*, *Strichliste App*.
- Semantisches HTML, `lang="de"`, Canonical, Open-Graph + Twitter-Cards.
- JSON-LD: `SoftwareApplication` + `FAQPage` (Rich Results).
- Eigener Fließtext-Block mit den Keywords (kein Keyword-Stuffing).

## Design-Quelle

Farben, Glass-Cards, Gold-/Mint-Gradients und die Getränke-Demo sind 1:1 aus der
App übernommen (`Striche/Theme/Theme.swift`, `Views/Main/DrinksView.swift`,
`DrinkCardView.swift`, `Models.swift` → `DrinkCatalog.presets`).

## Deployment (später)

Kann unter `striche-app.de` (Root) gehostet werden – die API liegt getrennt auf
`api.striche-app.de`. Z. B. als statischer Dienst in Coolify oder via GitHub Pages /
Netlify / Vercel. Vor dem Live-Gang die `og:image`-URL und Canonical prüfen.
