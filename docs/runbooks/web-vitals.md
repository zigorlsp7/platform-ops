# Core Web Vitals regressed

**Alert:** `CoreWebVitalsRegressed` (ticket)

## What fired

The 75th-percentile Largest Contentful Paint for a UI has been above 2.5 seconds
for six hours. 2.5s is the boundary Google draws between "good" and "needs
improvement", and p75 is the percentile it grades on.

This is measured in real browsers, from the RUM beacons the UIs send — not from
CI, not from a synthetic run on a fast machine with a warm cache.

## Whether it matters

Not urgently, and not never. Nothing is broken; the site is slower to become
useful than it should be, for a quarter of real visits. It is a ticket, and it
is the kind of ticket that is worth doing.

## How to see

The alert's own query, per UI:

```promql
histogram_quantile(0.75, sum by (job, le) (rate(rum_performance_seconds_bucket{metric_name="LCP"}[6h])))
```

The other vitals, which usually move together:

```promql
histogram_quantile(0.75, sum by (job, metric_name, le) (rate(rum_performance_seconds_bucket[6h])))
```

`CLS` and `INP` are collected too. INP replaced FID as a Core Web Vital in March
2024 and is the one that catches a heavy main thread.

## What to do

1. **Compare against a deploy.** A step change at a release is a bundle that
   grew, an image that lost its dimensions, or a font that started blocking.
2. **LCP is usually an image or a font.** Check that the LCP element has explicit
   dimensions and that webfonts use `display=swap`.
3. **INP is usually hydration** or a synchronous handler on the critical path.
4. **Confirm with the e2e performance suite** rather than a local reload — the
   cv UI has one under `apps/ui/e2e/performance.spec.ts` and it is the closest
   thing to a repeatable measurement.

If the regression is real and the fix is not small, close the alert with a
silence that has an end date and an issue behind it.
