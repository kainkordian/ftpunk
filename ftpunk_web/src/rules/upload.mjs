// Whether a finished activity should open the upload consent dialog by itself. Ported from Sources/FTPunkDomain/UploadPromptRule.swift (tests mirror
// IntervalsPerRiderTests.swift). The prompt only ever asks; it never uploads.

/** A workout, free ERG or resistance ride shorter than this is not worth a prompt. The manual button still works. */
export const MINIMUM_RIDE_SECONDS = 300;
const allowsEstimate = outcome => outcome === 'exhaustion' || outcome === 'finishedEarly';

/** `existingJob`: any upload job already made for this activity and account (queued, failed or uploaded). */
export function shouldAskToUpload({ session, hasConnection, askEnabled, existingJob = null }) {
  if (!hasConnection || !askEnabled || existingJob || session.isDemo || session.endedAtOffset == null) return false;
  if (session.training == null) return session.result != null && allowsEstimate(session.outcome);
  switch (session.outcome) {
    case 'completed': case 'aborted': return session.endedAtOffset >= MINIMUM_RIDE_SECONDS;
    default: return false; // interrupted rides (lost trainer, crash recovery) are never prompted
  }
}
