export type SnapshotEquality<T> = (left: T, right: T) => boolean;

/** Bounded browser-style navigation stacks. `visit` records the page being left. */
export class NavigationHistory<T> {
  private past: T[] = [];
  private future: T[] = [];

  constructor(
    private readonly maxEntries = 40,
    private readonly equals: SnapshotEquality<T> = Object.is,
  ) {
    if (!Number.isInteger(maxEntries) || maxEntries < 1) {
      throw new RangeError('maxEntries must be a positive integer');
    }
  }

  get canBack() { return this.past.length > 0; }
  get canForward() { return this.future.length > 0; }
  get backDestination(): T | null { return this.past.at(-1) ?? null; }
  get forwardDestination(): T | null { return this.future.at(-1) ?? null; }

  /** Record the current snapshot before a new destination is shown. */
  visit(current: T): void {
    const last = this.past.at(-1);
    if (last !== undefined && this.equals(last, current)) return;
    this.past.push(current);
    if (this.past.length > this.maxEntries) this.past.shift();
    this.future = [];
  }

  back(current: T): T | null {
    const destination = this.past.pop();
    if (destination === undefined) return null;
    this.pushBounded(this.future, current);
    return destination;
  }

  forward(current: T): T | null {
    const destination = this.future.pop();
    if (destination === undefined) return null;
    this.pushBounded(this.past, current);
    return destination;
  }

  clear(): void {
    this.past = [];
    this.future = [];
  }

  /** Update cached snapshots in both directions, for example after a saved-state change. */
  mapSnapshots(mapper: (snapshot: T) => T): void {
    this.past = this.past.map(mapper);
    this.future = this.future.map(mapper);
  }

  private pushBounded(stack: T[], snapshot: T): void {
    const lastIndex = stack.length - 1;
    if (lastIndex >= 0 && this.equals(stack[lastIndex], snapshot)) {
      stack[lastIndex] = snapshot;
      return;
    }
    stack.push(snapshot);
    if (stack.length > this.maxEntries) stack.shift();
  }
}
