import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import App from "./App";

// Apply persisted theme before first paint
const savedTheme = localStorage.getItem("theme") ?? "copper";
if (savedTheme !== "light") {
  document.documentElement.setAttribute("data-theme", savedTheme);
}
const savedFont = localStorage.getItem("font") ?? "nunito";
document.documentElement.setAttribute("data-font", savedFont);
const savedFontSize = localStorage.getItem("font-size") ?? "sm";
const fontSizeScale: Record<string, string> = { xs: "13px", sm: "14px", md: "16px", lg: "18px", xl: "20px" };
document.documentElement.style.fontSize = fontSizeScale[savedFontSize] ?? "14px";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
