import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { Dialog, DialogContent, DialogHeader } from "@/components/ui/dialog";
import { Tabs } from "@/components/ui/tabs";
import { CsvFileImport } from "@/components/import/CsvFileImport";
import { OfficeSheetImport } from "@/components/import/OfficeSheetImport";
import { SpreadsheetFormatGuide } from "@/components/import/SpreadsheetFormatGuide";

type Source = "office" | "upload";

interface Props {
  accountId: string;
  accountName: string;
  onClose: () => void;
}

/** Imports transactions into one account: from a spreadsheet in Office, or
 *  from CSV files (bank exports, or a sheet saved as CSV). Either way each
 *  source is checked before it's imported, and the format guide says how to
 *  fix one that doesn't pass. */
export function CsvUploadModal({ accountId, accountName, onClose }: Props) {
  const { data: office } = useQuery(queries.officeConfiguration());
  const officeOn = office?.configured ?? false;
  const [chosen, setChosen] = useState<Source | null>(null);
  const source: Source = chosen ?? (officeOn ? "office" : "upload");
  const [guideOpen, setGuideOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  return (
    <Dialog open onOpenChange={(open) => { if (!open && !busy) onClose(); }}>
      <DialogContent size="lg">
        <DialogHeader title="Import transactions" />

        <div className="space-y-3 px-5 pb-3 pt-4">
          <p className="text-xs text-muted-foreground">{accountName}</p>
          {officeOn && (
            <Tabs<Source>
              aria-label="Import from"
              size="sm"
              value={source}
              onChange={(next) => { if (!busy) setChosen(next); }}
              options={[
                { value: "office", label: "From Office" },
                { value: "upload", label: "Upload CSV" },
              ]}
            />
          )}
          <SpreadsheetFormatGuide open={guideOpen} onToggle={() => setGuideOpen((o) => !o)} />
        </div>

        {source === "office" ? (
          <OfficeSheetImport accountId={accountId} onClose={onClose} onNeedsFormat={() => setGuideOpen(true)} />
        ) : (
          <CsvFileImport accountId={accountId} onClose={onClose} onBusy={setBusy} onNeedsFormat={() => setGuideOpen(true)} />
        )}
      </DialogContent>
    </Dialog>
  );
}
