// Puerto de SofaScoreService.teamMatches() — match difuso de nombres de equipos
// tolerante a tildes, mayúsculas y abreviaciones.

function normalize(str) {
  return str
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .trim();
}

function words(str) {
  return normalize(str).split(/\s+/).filter(Boolean);
}

/**
 * ¿El nombre de equipo de la fuente (`sourceName`, tal cual lo da ESPN)
 * designa al mismo club que el nombre canónico de la app (`appName`)?
 *
 * Compara PALABRAS COMPLETAS, nunca subcadenas. La versión anterior hacía
 * `a.includes(w)` y "villarreal" contenía "real", así que quien tuviera
 * marcado el Real Madrid recibía avisos de todos los partidos del
 * Villarreal — y de Real Sociedad, Real Betis y Real Oviedo.
 *
 * Los nombres canónicos son siempre iguales o más cortos que los de ESPN
 * ("Betis" ⊂ "Real Betis", "Atlético" ⊂ "Atlético Madrid"), así que se exige
 * que TODAS las palabras significativas del canónico estén en el de origen.
 */
function teamMatches(sourceName, appName) {
  if (!sourceName || !appName) return false;

  const source = words(sourceName);
  const app    = words(appName);
  if (source.join(' ') === app.join(' ')) return true;

  const sourceSet = new Set(source);
  // "R. Sociedad" → ["sociedad"];  "Las Palmas" → ["palmas"]
  const significant = app.filter(w => w.length > 3);
  if (significant.length === 0) return false;

  return significant.every(w => sourceSet.has(w));
}

module.exports = { teamMatches };
