import { describe, it, expect } from "vitest";
import { isSevere } from "./severity";

describe("isSevere", () => {
  it("treats error and critical as the red tier", () => {
    expect(isSevere("error")).toBe(true);
    expect(isSevere("critical")).toBe(true);
  });

  it("leaves info and warning alone", () => {
    expect(isSevere("info")).toBe(false);
    expect(isSevere("warning")).toBe(false);
  });
});
