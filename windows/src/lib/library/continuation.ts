/** One automatic attempt per cursor; failures stay idle until an explicit retry. */
export class ContinuationGate {
  private attempted: string | null = null;

  reset() { this.attempted = null; }

  claim(context: string, cursor: string | null, nearBottom: boolean, busy: boolean, error: string | null): boolean {
    if (!cursor || !nearBottom || busy || error) return false;
    const key = JSON.stringify([context, cursor]);
    if (this.attempted === key) return false;
    this.attempted = key;
    return true;
  }
}
