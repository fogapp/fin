import { describe, it, expect } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithClient } from "@/test/queryClient";
import { ChartCard } from "./ChartCard";
import { chartFilename } from "@/lib/chartExport";

describe("ChartCard export menu", () => {
  it("offers plain and amounts-hidden PNG downloads", async () => {
    renderWithClient(<ChartCard title="Money flow"><div /></ChartCard>);

    await userEvent.setup().click(screen.getByRole("button", { name: "Download chart" }));

    expect(screen.getByRole("menuitem", { name: "Download PNG" })).toBeInTheDocument();
    expect(screen.getByRole("menuitem", { name: "Download PNG · amounts hidden" })).toBeInTheDocument();
  });

  it("toasts when the card body holds no chart", async () => {
    renderWithClient(<ChartCard title="Empty card"><p>No chart here</p></ChartCard>);

    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "Download chart" }));
    await user.click(screen.getByRole("menuitem", { name: "Download PNG" }));

    expect(await screen.findByText("No chart to export")).toBeInTheDocument();
  });
});

describe("chartFilename", () => {
  it("slugs titles and falls back for symbol-only input", () => {
    expect(chartFilename("Money flow")).toBe("money-flow.png");
    expect(chartFilename("Spend · by category (%)")).toBe("spend-by-category.png");
    expect(chartFilename("···")).toBe("chart.png");
  });
});
