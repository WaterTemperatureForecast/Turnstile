// Round calendar. A round is named by a date but opens at ROLLOVER_HOUR UTC on
// that date and closes at the same hour the next day. 08:00 UTC = 01:00 Pacific,
// 04:00 Eastern, 09:00 London, 17:00 Tokyo: a fresh round each morning for the
// Americas and Europe, one shared field for everyone.

export const ROLLOVER_HOUR = 8;

const MS_DAY = 86_400_000;

/** The round open at `now`: the UTC date of (now - ROLLOVER_HOUR hours). */
export function roundDate(now: Date = new Date()): string {
  return new Date(now.getTime() - ROLLOVER_HOUR * 3_600_000).toISOString().slice(0, 10);
}

export function nextDay(date: string): string {
  return new Date(Date.parse(date + "T00:00:00Z") + MS_DAY).toISOString().slice(0, 10);
}

export function addDays(date: string, n: number): string {
  return new Date(Date.parse(date + "T00:00:00Z") + n * MS_DAY).toISOString().slice(0, 10);
}

/** Round date n days before the round open now. */
export function daysAgo(n: number, now: Date = new Date()): string {
  return addDays(roundDate(now), -n);
}

/** ISO instant at which the round for `date` closes. */
export function closesAt(date: string): string {
  return `${nextDay(date)}T${String(ROLLOVER_HOUR).padStart(2, "0")}:00:00Z`;
}

export function isDate(s: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(s) && !isNaN(Date.parse(s + "T00:00:00Z"));
}
