import { useHashParam } from "@/hooks/useHashParam";
import { usePageTimeframe } from "@/hooks/useTimeframeButtons";
import { SectionRailNav } from "@/components/layout/SectionRailNav";
import { PortfolioSection } from "./investments/PortfolioSection";
import { InvestmentFlowSection } from "./investments/InvestmentFlowSection";
import { TransactionsSection } from "./investments/TransactionsSection";
import { CostBasisSection } from "./investments/CostBasisSection";
import { CryptoSection } from "./investments/CryptoSection";
import { RealEstateSection } from "./investments/RealEstateSection";
import { NetWorth } from "./NetWorth";
import { Equity } from "./Equity";

const SECTIONS = [
  { id: "net_worth",   label: "Net Worth" },
  { id: "portfolio",   label: "Portfolio" },
  { id: "buys",        label: "Buys" },
  { id: "sells",       label: "Sells" },
  { id: "dividends",   label: "Dividends" },
  { id: "transactions", label: "Transactions" },
  { id: "cost_basis",  label: "Cost Basis" },
  { id: "crypto",      label: "Crypto" },
  { id: "real_estate", label: "Real Estate" },
  { id: "equity",      label: "Equity" },
];

export function Investments() {
  const [section, setSection] = useHashParam("section");
  // "performance" folded into Portfolio; keep old deep links working.
  const active = !section || section === "performance" ? "portfolio" : section;
  // One page-scoped timeframe; the control renders inside the active
  // section's primary chart card header.
  const timeframe = usePageTimeframe("investments", "investments-timeframe");

  return (
    <div className="flex h-full flex-col md:flex-row">
      {/* Left nav — sidebar on desktop, horizontal tabs on mobile */}
      <SectionRailNav title="Investments" sections={SECTIONS} active={active} onSelect={setSection} />

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {active === "portfolio"   && <PortfolioSection />}
        {active === "buys"        && <InvestmentFlowSection kind="buys" timeframe={timeframe} />}
        {active === "sells"       && <InvestmentFlowSection kind="sells" timeframe={timeframe} />}
        {active === "dividends"   && <InvestmentFlowSection kind="dividends" timeframe={timeframe} />}
        {active === "transactions" && <TransactionsSection />}
        {active === "cost_basis"  && <CostBasisSection />}
        {active === "crypto"      && <CryptoSection timeframe={timeframe} />}
        {active === "real_estate" && <RealEstateSection />}
        {active === "net_worth"   && <NetWorth />}
        {active === "equity"      && <Equity />}
      </div>
    </div>
  );
}
