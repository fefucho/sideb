/** Uses the operating system's local time, without network or location access. */
export function homeGreetingKey(date = new Date()): 'app.home.morning' | 'app.home.afternoon' | 'app.home.evening' {
  const hour = date.getHours();
  return hour >= 6 && hour < 12 ? 'app.home.morning'
    : hour >= 12 && hour < 20 ? 'app.home.afternoon' : 'app.home.evening';
}
