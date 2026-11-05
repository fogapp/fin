import { describe, it, expect, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { Sidebar } from "@/components/layout/Sidebar";

describe("Sidebar: collapsed rail", () => {
  beforeEach(() => localStorage.clear());

  it("renders icon links with real classes when collapsed (Radix Slot must not stringify a className function)", () => {
    localStorage.setItem("sidebar-collapsed", "true");
    render(<MemoryRouter><Sidebar /></MemoryRouter>);

    const links = screen.getAllByRole("link");
    expect(links).toHaveLength(13);
    for (const link of links) {
      // Regression guard: Tooltip.Trigger asChild coerced NavLink's
      // function-form className into its source string ("({ isActive }) =>…"),
      // stripping every style from the collapsed rail.
      expect(link.className).not.toContain("=>");
      expect(link.className).toContain("justify-center");
      expect(link.querySelector("svg")).not.toBeNull();
      // Icon-only: no visible label text.
      expect(link.textContent).toBe("");
    }
  });

  it("renders labels and no tooltips when expanded", () => {
    render(<MemoryRouter><Sidebar /></MemoryRouter>);

    expect(screen.getByRole("link", { name: /Dashboard/ })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Investments/ })).toBeInTheDocument();
    const links = screen.getAllByRole("link");
    expect(links).toHaveLength(13);
    for (const link of links) {
      expect(link.className).not.toContain("=>");
      expect(link.className).toContain("gap-3");
    }
  });
});
