import { describe, it, expect } from "vitest";
import { buildGroupedRows, toggledSet } from "./tableEngine";

interface Item { id: string; group: string }
const item = (id: string, group: string): Item => ({ id, group });

const byGroup = (i: Item) => i.group;

describe("buildGroupedRows", () => {
  it("returns flat tx rows with sequential pIdx when groupKey is null", () => {
    const items = [item("a", "g1"), item("b", "g2")];
    expect(buildGroupedRows({ items, groupKey: null, collapsed: new Set() })).toEqual([
      { type: "tx", tx: items[0], group: "", pIdx: 0 },
      { type: "tx", tx: items[1], group: "", pIdx: 1 },
    ]);
  });

  it("interleaves header rows with counts back-patched per group", () => {
    const items = [item("a", "g1"), item("b", "g1"), item("c", "g2")];
    expect(buildGroupedRows({ items, groupKey: byGroup, collapsed: new Set() })).toEqual([
      { type: "header", label: "g1", count: 2 },
      { type: "tx", tx: items[0], group: "g1", pIdx: 0 },
      { type: "tx", tx: items[1], group: "g1", pIdx: 1 },
      { type: "header", label: "g2", count: 1 },
      { type: "tx", tx: items[2], group: "g2", pIdx: 2 },
    ]);
  });

  it("maps group keys through groupLabel, and collapses by label", () => {
    const items = [item("a", "2026-01"), item("b", "2026-02")];
    const rows = buildGroupedRows({
      items,
      groupKey: byGroup,
      groupLabel: (k) => (k === "2026-01" ? "January 2026" : "February 2026"),
      collapsed: new Set(["January 2026"]),
    });
    expect(rows).toEqual([
      { type: "header", label: "January 2026", count: 1 },
      { type: "header", label: "February 2026", count: 1 },
      { type: "tx", tx: items[1], group: "February 2026", pIdx: 0 },
    ]);
  });

  it("keeps counting rows hidden by a collapsed group, and pIdx numbers only rendered rows", () => {
    const items = [item("a", "g1"), item("b", "g1"), item("c", "g2"), item("d", "g2")];
    const rows = buildGroupedRows({ items, groupKey: byGroup, collapsed: new Set(["g1"]) });
    expect(rows).toEqual([
      { type: "header", label: "g1", count: 2 },
      { type: "header", label: "g2", count: 2 },
      { type: "tx", tx: items[2], group: "g2", pIdx: 0 },
      { type: "tx", tx: items[3], group: "g2", pIdx: 1 },
    ]);
  });

  it("re-opens a header when a group's label reappears non-adjacently (caller sorts groups together)", () => {
    // Mirrors the original inline algorithm: adjacency defines groups, so an
    // unsorted input yields repeated headers rather than merged counts.
    const items = [item("a", "g1"), item("b", "g2"), item("c", "g1")];
    const rows = buildGroupedRows({ items, groupKey: byGroup, collapsed: new Set() });
    expect(rows.filter((r) => r.type === "header")).toEqual([
      { type: "header", label: "g1", count: 1 },
      { type: "header", label: "g2", count: 1 },
      { type: "header", label: "g1", count: 1 },
    ]);
  });
});

describe("toggledSet", () => {
  it("adds a missing value and removes a present one, without mutating the input", () => {
    const start = new Set(["a"]);
    const added = toggledSet(start, "b");
    expect([...added].sort()).toEqual(["a", "b"]);
    const removed = toggledSet(added, "a");
    expect([...removed]).toEqual(["b"]);
    expect([...start]).toEqual(["a"]);
  });
});
