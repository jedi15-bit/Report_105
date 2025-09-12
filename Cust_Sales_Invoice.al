report 50105 "Customer Sales Invoice"
{
    RDLCLayout = './Layouts/SalesInvioceTermCon.rdl';
    UsageCategory = ReportsAndAnalysis;
    ApplicationArea = All;
    Caption = 'Custom Tax Invoice';

    dataset
    {
        dataitem(SIH; "Sales Invoice Header")
        {
            RequestFilterFields = "No.";

            // Invoice header fields
            column(InvoiceNo; "No.") { }
            column(PostingDate; "Posting Date") { }
            column(ExternalDocNo; "External Document No.") { } // PO No.
            column(CurrencyCode; "Currency Code") { }

            // Bill To (from header)
            column(BillToName; "Bill-to Name") { }
            column(BillToAddress; "Bill-to Address") { }
            column(BillToCity; "Bill-to City") { }
            column(BillToPostCode; "Bill-to Post Code") { }
            column(BillToGSTIN; CustomerGSTIN) { }

            // Ship To
            column(ShipToName; "Ship-to Name") { }
            column(ShipToAddress; "Ship-to Address") { }
            column(ShipToCity; "Ship-to City") { }
            column(ShipToPostCode; "Ship-to Post Code") { }

            // Seller (Company Information)
            column(SellerName; SellerName) { }
            column(SellerAddress; SellerAddress) { }
            column(SellerGSTIN; SellerGSTIN) { }
            column(SellerPAN; SellerPAN) { }
            column(SellerFSSAI; SellerFSSAI) { }
            column(SellerCIN; SellerCIN) { }

            // Totals
            column(SubTotal; TotalBasic) { }
            column(TotalTaxable; TotalTaxable) { }
            column(TotalCGST; TotalCGST) { }
            column(TotalSGST; TotalSGST) { }
            column(TotalIGST; TotalIGST) { }
            column(GrandTotal; GrandTotal) { }
            column(AmountInWords; AmountInWords) { }

            dataitem(SIL; "Sales Invoice Line")
            {
                DataItemLink = "Document No." = field("No.");

                // Line fields
                column(LineNo; "Line No.") { }
                column(Description; Description) { }
                column(HSN; "HSN/SAC Code") { }
                column(Quantity; Quantity) { }
                column(UnitPrice; "Unit Price") { }
                column(LineAmount; "Line Amount") { }
                column(LineDiscPct; "Line Discount %") { }
                column(LineDiscAmt; "Line Discount Amount") { }

                // GST per line
                column(CGSTPct; CGSTPct) { }
                column(CGSTAmt; CGSTAmt) { }
                column(SGSTPct; SGSTPct) { }
                column(SGSTAmt; SGSTAmt) { }
                column(IGSTPct; IGSTPct) { }
                column(IGSTAmt; IGSTAmt) { }

                // Taxable value and line total
                column(TaxableValue; TaxableValue) { }
                column(LineTotalValue; LineTotalValue) { }

                trigger OnAfterGetRecord()
                begin
                    // Taxable = Line Amount - Line Discount
                    TaxableValue := "Line Amount" - "Line Discount Amount";

                    // Get GST per line
                    GetGSTForLine(SIL, CGSTPct, CGSTAmt, SGSTPct, SGSTAmt, IGSTPct, IGSTAmt);

                    // Line total incl GST
                    LineTotalValue := TaxableValue + CGSTAmt + SGSTAmt + IGSTAmt;

                    // Accumulate totals
                    TotalBasic += "Line Amount";
                    TotalTaxable += TaxableValue;
                    TotalCGST += CGSTAmt;
                    TotalSGST += SGSTAmt;
                    TotalIGST += IGSTAmt;
                end;
            }

            trigger OnAfterGetRecord()
            var
                Cust: Record Customer;
            begin
                // Company (Seller) details
                if CompanyInfo.Get() then begin
                    SellerName := CompanyInfo.Name;
                    SellerAddress := CompanyInfo.Address;
                    SellerGSTIN := CompanyInfo."VAT Registration No.";
                    SellerPAN := CompanyInfo."Registration No."; // PAN (if used here or via extension)
                    SellerFSSAI := CompanyInfo."FSSAI No.";      // custom field via extension
                    SellerCIN := CompanyInfo."CIN No.";          // custom field via extension
                end;

                // Customer GSTIN
                if Cust.Get("Bill-to Customer No.") then
                    CustomerGSTIN := Cust."VAT Registration No.";

                // Grand Total
                GrandTotal := TotalTaxable + TotalCGST + TotalSGST + TotalIGST;

                // Convert to words
                AmountInWords := GetAmountInWords(GrandTotal, "Currency Code");
            end;
        }
    }

    requestpage
    {
        layout
        {
            area(content)
            {
                group(Options)
                {
                    field(InvoiceNoFilter; SIH."No.")
                    {
                        ApplicationArea = All;
                        Caption = 'Invoice No.';
                    }
                }
            }
        }
    }

    var
        // Company Info vars
        CompanyInfo: Record "Company Information";
        SellerName: Text[100];
        SellerAddress: Text[100];
        SellerGSTIN: Code[20];
        SellerPAN: Code[20];
        SellerFSSAI: Code[20];
        SellerCIN: Code[30];

        // Customer
        CustomerGSTIN: Code[20];

        // GST fields
        CGSTPct: Decimal;
        CGSTAmt: Decimal;
        SGSTPct: Decimal;
        SGSTAmt: Decimal;
        IGSTPct: Decimal;
        IGSTAmt: Decimal;

        // Totals
        TaxableValue: Decimal;
        LineTotalValue: Decimal;
        TotalBasic: Decimal;
        TotalTaxable: Decimal;
        TotalCGST: Decimal;
        TotalSGST: Decimal;
        TotalIGST: Decimal;
        GrandTotal: Decimal;
        AmountInWords: Text[250];

    local procedure GetGSTForLine(var Line: Record "Sales Invoice Line";
      var CGSTPct: Decimal; var CGSTAmt: Decimal;
      var SGSTPct: Decimal; var SGSTAmt: Decimal;
      var IGSTPct: Decimal; var IGSTAmt: Decimal)
    var
        GSTEntry: Record "Detailed GST Ledger Entry"; // India localization table
    begin
        Clear(CGSTPct);
        Clear(CGSTAmt);
        Clear(SGSTPct);
        Clear(SGSTAmt);
        Clear(IGSTPct);
        Clear(IGSTAmt);

        GSTEntry.SetRange("Document No.", Line."Document No.");
        GSTEntry.SetRange("Document Line No.", Line."Line No.");

        if GSTEntry.FindSet() then
            repeat
                case GSTEntry."GST Component Code" of
                    'CGST':
                        begin
                            CGSTPct := GSTEntry."GST %";
                            CGSTAmt += GSTEntry."GST Amount";
                        end;
                    'SGST':
                        begin
                            SGSTPct := GSTEntry."GST %";
                            SGSTAmt += GSTEntry."GST Amount";
                        end;
                    'IGST':
                        begin
                            IGSTPct := GSTEntry."GST %";
                            IGSTAmt += GSTEntry."GST Amount";
                        end;
                end;
            until GSTEntry.Next() = 0;
    end;


    local procedure GetAmountInWords(Amount: Decimal; CurrCode: Code[10]): Text[250]
    var
        CheckReport: Report "Check";
        Txt: array[2] of Text[80];
    begin
        CheckReport.InitTextVariable();
        CheckReport.FormatNoText(Txt, Round(Amount, 0.01), CurrCode);
        exit(UpperCase(DelChr(Txt[1] + ' ' + Txt[2], '=', ' ')));
    end;
}