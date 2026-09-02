// Casador de nombres para la Champions.
//
// `teamMatches` (el de La Liga) exige que todas las palabras significativas del
// nombre canónico de la app estén en el nombre de ESPN. Con los clubes de La
// Liga funciona porque los canónicos son recortes del nombre de ESPN («Betis»
// ⊂ «Real Betis»). En la Champions no: la app dice «Inter de Milán» y ESPN
// «Internazionale», «Oporto» y «FC Porto», «Nápoles» y «Napoli», «Brujas» y
// «Club Brugge». Con el casador de palabras, quien siguiera a esos equipos no
// recibiría ni un aviso, sin ningún error que lo delatara.
//
// Aquí se hace al revés: el nombre de ESPN se traduce al canónico con el mismo
// mapa que usa `scripts/update_champions.py` en el repositorio de la Champions,
// y se compara con igualdad. Los dos mapas deben mantenerse iguales; si ESPN
// renombra un club hay que tocar los dos.

const ESPN_A_CANONICO = {
  'AEK Athens': 'AEK Atenas',
  'AS Roma': 'Roma', 'Roma': 'Roma',
  'Arsenal': 'Arsenal',
  'Aston Villa': 'Aston Villa',
  'Atletico Madrid': 'Atlético de Madrid',
  'Atlético Madrid': 'Atlético de Madrid',
  'Atlético de Madrid': 'Atlético de Madrid',
  'Barcelona': 'FC Barcelona', 'FC Barcelona': 'FC Barcelona',
  'Bayern Munich': 'Bayern de Múnich', 'Bayern München': 'Bayern de Múnich',
  'Bodo/Glimt': 'Bodø/Glimt', 'Bodø/Glimt': 'Bodø/Glimt',
  'Borussia Dortmund': 'Borussia Dortmund', 'Dortmund': 'Borussia Dortmund',
  'Club Brugge': 'Brujas', 'Club Brugge KV': 'Brujas',
  'Como': 'Como',
  'FC Porto': 'Oporto', 'Porto': 'Oporto',
  'Fenerbahce': 'Fenerbahçe', 'Fenerbahçe': 'Fenerbahçe',
  'Feyenoord Rotterdam': 'Feyenoord', 'Feyenoord': 'Feyenoord',
  'Galatasaray': 'Galatasaray',
  'Internazionale': 'Inter de Milán', 'Inter Milan': 'Inter de Milán', 'Inter': 'Inter de Milán',
  'LASK Linz': 'LASK', 'LASK': 'LASK',
  'Lens': 'Lens', 'RC Lens': 'Lens',
  'Lille': 'Lille', 'Lille OSC': 'Lille',
  'Liverpool': 'Liverpool',
  'Manchester City': 'Manchester City', 'Man City': 'Manchester City',
  'Manchester United': 'Manchester United', 'Man United': 'Manchester United',
  'Napoli': 'Nápoles',
  'PSV Eindhoven': 'PSV', 'PSV': 'PSV',
  'Paris Saint-Germain': 'Paris Saint-Germain', 'Paris Saint Germain': 'Paris Saint-Germain', 'PSG': 'Paris Saint-Germain',
  'RB Leipzig': 'RB Leipzig',
  'Real Betis': 'Real Betis',
  'Real Madrid': 'Real Madrid',
  'Sabah FK': 'Sabah', 'Sabah': 'Sabah',
  'Shakhtar Donetsk': 'Shajtar Donetsk',
  'Slavia Prague': 'Slavia de Praga',
  'Slovan Bratislava': 'Slovan Bratislava',
  'Sporting CP': 'Sporting de Portugal', 'Sporting Lisbon': 'Sporting de Portugal',
  'VfB Stuttgart': 'Stuttgart',
  'Viking FK': 'Viking', 'Viking': 'Viking',
  'Villarreal': 'Villarreal',
};

function plegar(s) {
  return String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
}

// Índice sin acentos ni mayúsculas, por si ESPN cambia la grafía.
const INDICE = new Map(Object.entries(ESPN_A_CANONICO).map(([k, v]) => [plegar(k), v]));

/** Nombre canónico de la app para un nombre de ESPN, o el mismo si no está. */
function canonicalChampionsName(espnName) {
  if (!espnName) return '';
  return ESPN_A_CANONICO[espnName.trim()] ?? INDICE.get(plegar(espnName)) ?? espnName.trim();
}

/** ¿El nombre de ESPN `sourceName` es el club que la app llama `appName`? */
function championsTeamMatches(sourceName, appName) {
  if (!sourceName || !appName) return false;
  return plegar(canonicalChampionsName(sourceName)) === plegar(appName);
}

module.exports = { championsTeamMatches, canonicalChampionsName };
