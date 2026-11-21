unit UnitNFCeParser.Service;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  ENFCeCaptchaException = class(Exception);
  ENFCeParseException = class(Exception);

  TNFCeItemParsed = record
    NumeroItem: Integer;
    CodigoFornecedor: string;
    EAN: string;
    Descricao: string;
    Unidade: string;
    Quantidade: Double;
    ValorUnitario: Double;
    ValorTotal: Double;
    Desconto: Double;
    NCM: string;
  end;

  TNFCeParsed = record
    Chave: string;
    Url: string;
    Numero: string;
    Serie: string;
    DataEmissao: TDateTime;
    CnpjEmitente: string;
    NomeEmitente: string;
    ValorTotal: Double;
    ValorDesconto: Double;
    FormaPagamento: string;
    Itens: TArray<TNFCeItemParsed>;
  end;

  TNFCeParserService = class
  private
    class function SomenteDigitos(const Texto: string): string; static;
    class function LimparHtml(const Html: string): string; static;
    class function DecodificarEntidadesHtml(const Texto: string): string; static;
    class function ParseNumero(const Texto: string): Double; static;
    class function ExtrairTagXml(const Bloco, Tag: string): string; static;
    class function ExtrairChaveDaUrl(const Url: string): string; static;
    class function BaixarHtmlUrl(const Url: string): string; static;
    class function DetectarCaptchaOuBloqueio(const Html: string): Boolean; static;
    class function MapearPagamentoXML(const TPag: string): string; static;
    class function ParseDataBR(const Texto: string; out DataRes: TDateTime): Boolean; static;
    class function ParseFromHtml(const Html, UrlOrigem: string): TNFCeParsed; static;
  public
    class function ParseFromUrl(const AUrl: string): TNFCeParsed; static;
    class function ParseFromXml(const AXml: string): TNFCeParsed; static;
  end;

implementation

uses
  System.StrUtils,
  System.DateUtils,
  System.Math,
  System.RegularExpressions,
  System.Net.URLClient,
  System.Net.HttpClient,
  System.Net.HttpClientComponent;

{ TNFCeParserService }

class function TNFCeParserService.SomenteDigitos(const Texto: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in Texto do
    if CharInSet(Ch, ['0'..'9']) then
      Result := Result + Ch;
end;

class function TNFCeParserService.DecodificarEntidadesHtml(const Texto: string): string;
var
  R: string;
  Match: TMatch;
  Code: Integer;
begin
  R := Texto;
  R := StringReplace(R, '&nbsp;', ' ', [rfReplaceAll, rfIgnoreCase]);
  R := StringReplace(R, '&amp;', '&', [rfReplaceAll, rfIgnoreCase]);
  R := StringReplace(R, '&quot;', '"', [rfReplaceAll, rfIgnoreCase]);
  R := StringReplace(R, '&#39;', '''', [rfReplaceAll, rfIgnoreCase]);
  R := StringReplace(R, '&apos;', '''', [rfReplaceAll, rfIgnoreCase]);
  R := StringReplace(R, '&lt;', '<', [rfReplaceAll, rfIgnoreCase]);
  R := StringReplace(R, '&gt;', '>', [rfReplaceAll, rfIgnoreCase]);
  R := StringReplace(R, '&aacute;', 'á', [rfReplaceAll]);
  R := StringReplace(R, '&Aacute;', 'Á', [rfReplaceAll]);
  R := StringReplace(R, '&agrave;', 'à', [rfReplaceAll]);
  R := StringReplace(R, '&acirc;', 'â', [rfReplaceAll]);
  R := StringReplace(R, '&atilde;', 'ã', [rfReplaceAll]);
  R := StringReplace(R, '&Atilde;', 'Ã', [rfReplaceAll]);
  R := StringReplace(R, '&eacute;', 'é', [rfReplaceAll]);
  R := StringReplace(R, '&Eacute;', 'É', [rfReplaceAll]);
  R := StringReplace(R, '&ecirc;', 'ê', [rfReplaceAll]);
  R := StringReplace(R, '&iacute;', 'í', [rfReplaceAll]);
  R := StringReplace(R, '&Iacute;', 'Í', [rfReplaceAll]);
  R := StringReplace(R, '&oacute;', 'ó', [rfReplaceAll]);
  R := StringReplace(R, '&Oacute;', 'Ó', [rfReplaceAll]);
  R := StringReplace(R, '&ocirc;', 'ô', [rfReplaceAll]);
  R := StringReplace(R, '&otilde;', 'õ', [rfReplaceAll]);
  R := StringReplace(R, '&uacute;', 'ú', [rfReplaceAll]);
  R := StringReplace(R, '&Uacute;', 'Ú', [rfReplaceAll]);
  R := StringReplace(R, '&ccedil;', 'ç', [rfReplaceAll]);
  R := StringReplace(R, '&Ccedil;', 'Ç', [rfReplaceAll]);

  // Entidades numericas &#NNN;
  for Match in TRegEx.Matches(R, '&#(\d+);') do
  begin
    if TryStrToInt(Match.Groups[1].Value, Code) and (Code > 0) and (Code < 65535) then
      R := StringReplace(R, Match.Value, Char(Code), [rfReplaceAll]);
  end;

  // Entidades hexadecimais &#xHH;
  for Match in TRegEx.Matches(R, '&#x([0-9a-fA-F]+);') do
  begin
    if TryStrToInt('$' + Match.Groups[1].Value, Code) and (Code > 0) and (Code < 65535) then
      R := StringReplace(R, Match.Value, Char(Code), [rfReplaceAll]);
  end;

  Result := R;
end;

class function TNFCeParserService.LimparHtml(const Html: string): string;
begin
  Result := TRegEx.Replace(Html, '<[^>]+>', ' ');
  Result := DecodificarEntidadesHtml(Result);
  Result := TRegEx.Replace(Result, '\s+', ' ').Trim;
end;

class function TNFCeParserService.ParseNumero(const Texto: string): Double;
var
  S: string;
  FS: TFormatSettings;
  Temp: string;
  Ch: Char;
begin
  Result := 0;
  S := Trim(Texto);
  if S.IsEmpty then
    Exit;

  Temp := '';
  for Ch in S do
  begin
    if CharInSet(Ch, ['0'..'9', ',', '.', '-']) then
      Temp := Temp + Ch;
  end;

  if Temp.IsEmpty then
    Exit;

  // Se houver virgula, assume formato BR (1.234,56 -> 1234.56)
  if Pos(',', Temp) > 0 then
  begin
    Temp := StringReplace(Temp, '.', '', [rfReplaceAll]);
    Temp := StringReplace(Temp, ',', '.', [rfReplaceAll]);
  end;

  FS := TFormatSettings.Invariant;
  TryStrToFloat(Temp, Result, FS);
end;

class function TNFCeParserService.ExtrairTagXml(const Bloco, Tag: string): string;
var
  M: TMatch;
begin
  Result := '';
  M := TRegEx.Match(Bloco, '<(?:\w+:)?' + Tag + '(?:\s+[^>]*)?>(.*?)</(?:\w+:)?' + Tag + '>',
    [roSingleLine, roIgnoreCase]);
  if M.Success then
    Result := DecodificarEntidadesHtml(M.Groups[1].Value).Trim;
end;

class function TNFCeParserService.ExtrairChaveDaUrl(const Url: string): string;
var
  M: TMatch;
  Digitos: string;
begin
  Result := '';
  M := TRegEx.Match(Url, '(?:p=|chNFe=)([0-9]{44})', [roIgnoreCase]);
  if M.Success then
    Exit(M.Groups[1].Value);

  M := TRegEx.Match(Url, '(\d{44})');
  if M.Success then
    Exit(M.Groups[1].Value);

  Digitos := SomenteDigitos(Url);
  if Length(Digitos) >= 44 then
    Result := Copy(Digitos, 1, 44);
end;

class function TNFCeParserService.BaixarHtmlUrl(const Url: string): string;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  Bytes: TBytes;
  ContentType: string;
begin
  Client := THTTPClient.Create;
  try
    Client.HandleRedirects := True;
    Client.MaxRedirects := 10;
    Client.ConnectionTimeout := 15000;
    Client.ResponseTimeout := 25000;
    Client.UserAgent :=
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
    Client.CustomHeaders['Accept'] := 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
    Client.CustomHeaders['Accept-Language'] := 'pt-BR,pt;q=0.9,en-US;q=0.8';

    Resp := Client.Get(Url);
    if Resp.StatusCode >= 400 then
      raise ENFCeParseException.CreateFmt(
        'SEFAZ retornou HTTP %d ao consultar o QR Code. Tente importar o arquivo XML da nota.',
        [Resp.StatusCode]
      );

    SetLength(Bytes, Resp.ContentStream.Size);
    if Length(Bytes) > 0 then
    begin
      Resp.ContentStream.Position := 0;
      Resp.ContentStream.ReadBuffer(Bytes[0], Length(Bytes));
    end;

    ContentType := LowerCase(Resp.HeaderValue['Content-Type']);
    if ContentType.Contains('iso-8859-1') or ContentType.Contains('windows-1252') then
      Result := TEncoding.GetEncoding(1252).GetString(Bytes)
    else
    begin
      try
        Result := TEncoding.UTF8.GetString(Bytes);
      except
        Result := TEncoding.GetEncoding(1252).GetString(Bytes);
      end;
    end;
  finally
    Client.Free;
  end;
end;

class function TNFCeParserService.DetectarCaptchaOuBloqueio(const Html: string): Boolean;
var
  LowerHtml: string;
begin
  LowerHtml := LowerCase(Html);
  Result :=
    LowerHtml.Contains('g-recaptcha') or
    LowerHtml.Contains('hcaptcha') or
    LowerHtml.Contains('cf-turnstile') or
    LowerHtml.Contains('captcha') or
    LowerHtml.Contains('just a moment') or
    LowerHtml.Contains('nao sou um robo') or
    LowerHtml.Contains('não sou um robô');
end;

class function TNFCeParserService.MapearPagamentoXML(const TPag: string): string;
var
  Cod: string;
begin
  Cod := Trim(TPag);
  if Cod = '01' then Result := 'DINHEIRO'
  else if Cod = '02' then Result := 'CHEQUE'
  else if Cod = '03' then Result := 'CARTAO CREDITO'
  else if Cod = '04' then Result := 'CARTAO DEBITO'
  else if Cod = '05' then Result := 'CREDITO LOJA'
  else if (Cod = '10') or (Cod = '11') then Result := 'VALE'
  else if Cod = '15' then Result := 'BOLETO'
  else if (Cod = '17') or (Cod = '20') then Result := 'PIX'
  else Result := 'OUTROS';
end;

class function TNFCeParserService.ParseDataBR(const Texto: string; out DataRes: TDateTime): Boolean;
var
  M: TMatch;
  D, Mes, A: Word;
begin
  Result := False;
  DataRes := Date;
  M := TRegEx.Match(Texto, '(\d{2})/(\d{2})/(\d{4})');
  if M.Success then
  begin
    D := StrToIntDef(M.Groups[1].Value, 0);
    Mes := StrToIntDef(M.Groups[2].Value, 0);
    A := StrToIntDef(M.Groups[3].Value, 0);
    Result := TryEncodeDate(A, Mes, D, DataRes);
  end
  else
  begin
    M := TRegEx.Match(Texto, '(\d{4})-(\d{2})-(\d{2})');
    if M.Success then
    begin
      A := StrToIntDef(M.Groups[1].Value, 0);
      Mes := StrToIntDef(M.Groups[2].Value, 0);
      D := StrToIntDef(M.Groups[3].Value, 0);
      Result := TryEncodeDate(A, Mes, D, DataRes);
    end;
  end;
end;

class function TNFCeParserService.ParseFromHtml(const Html, UrlOrigem: string): TNFCeParsed;
var
  Lista: TList<TNFCeItemParsed>;
  MatchItem, MatchAux: TMatch;
  MatchesItens: TMatchCollection;
  BlocoItem, BlocoTab, TextoLimpo, LinhaTxt: string;
  Item: TNFCeItemParsed;
  Idx: Integer;
  DtAux: TDateTime;

  function ExtrairSpanPorClasse(const Bloco, Classe: string): string;
  var
    M: TMatch;
  begin
    Result := '';
    M := TRegEx.Match(
      Bloco,
      'class\s*=\s*["''][^"'']*\b' + Classe + '\b[^"'']*["''][^>]*>(.*?)</(?:span|div|strong|td)>',
      [roSingleLine, roIgnoreCase]
    );
    if M.Success then
      Result := LimparHtml(M.Groups[1].Value);
  end;

  function ExtrairNumeroLinhaTabela(const Padrao: string): Double;
  var
    M: TMatch;
  begin
    Result := 0;
    M := TRegEx.Match(Html, Padrao, [roSingleLine, roIgnoreCase]);
    if M.Success then
      Result := ParseNumero(LimparHtml(M.Groups[1].Value));
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Url := UrlOrigem;
  Result.Chave := ExtrairChaveDaUrl(UrlOrigem);
  Result.DataEmissao := Date;
  Result.FormaPagamento := 'DINHEIRO';

  // Tenta extrair chave do HTML caso a URL seja encurtada
  if Result.Chave.IsEmpty then
  begin
    MatchAux := TRegEx.Match(Html, '(\d{4}\s*\d{4}\s*\d{4}\s*\d{4}\s*\d{4}\s*\d{4}\s*\d{4}\s*\d{4}\s*\d{4}\s*\d{4}\s*\d{4})');
    if MatchAux.Success then
      Result.Chave := SomenteDigitos(MatchAux.Groups[1].Value);
  end;

  // Emitente (SEFAZ-MS / padrao nacional NFC-e)
  Result.NomeEmitente := ExtrairSpanPorClasse(Html, 'txtTopo');
  if Result.NomeEmitente.IsEmpty then
  begin
    MatchAux := TRegEx.Match(Html, 'id\s*=\s*["'']u20["''][^>]*>(.*?)</', [roSingleLine, roIgnoreCase]);
    if MatchAux.Success then
      Result.NomeEmitente := LimparHtml(MatchAux.Groups[1].Value);
  end;

  // CNPJ Emitente
  MatchAux := TRegEx.Match(Html, 'CNPJ\s*:?\s*(\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2})', [roIgnoreCase]);
  if MatchAux.Success then
    Result.CnpjEmitente := SomenteDigitos(MatchAux.Groups[1].Value);

  // Numero, Serie e Emissao
  MatchAux := TRegEx.Match(Html, 'N[úu]mero\s*:?\s*(\d+)', [roIgnoreCase]);
  if MatchAux.Success then
    Result.Numero := MatchAux.Groups[1].Value;

  MatchAux := TRegEx.Match(Html, 'S[ée]rie\s*:?\s*(\d+)', [roIgnoreCase]);
  if MatchAux.Success then
    Result.Serie := MatchAux.Groups[1].Value;

  MatchAux := TRegEx.Match(Html, 'Emiss[ãa]o\s*:?\s*(\d{2}/\d{2}/\d{4})', [roIgnoreCase]);
  if MatchAux.Success and ParseDataBR(MatchAux.Groups[1].Value, DtAux) then
    Result.DataEmissao := DtAux;

  // Extracao de itens (padrao <tr id="Item + N">)
  Lista := TList<TNFCeItemParsed>.Create;
  try
    MatchesItens := TRegEx.Matches(Html, '<tr[^>]*id\s*=\s*["'']Item[^"'']*["''][^>]*>(.*?)</tr>', [roSingleLine, roIgnoreCase]);
    if MatchesItens.Count = 0 then
    begin
      // Fallback: extrair linhas de <table id="tabResult">
      MatchAux := TRegEx.Match(Html, '<table[^>]*id\s*=\s*["'']tabResult["''][^>]*>(.*?)</table>', [roSingleLine, roIgnoreCase]);
      if MatchAux.Success then
      begin
        BlocoTab := MatchAux.Groups[1].Value;
        MatchesItens := TRegEx.Matches(BlocoTab, '<tr[^>]*>(.*?)</tr>', [roSingleLine, roIgnoreCase]);
      end;
    end;

    Idx := 1;
    for MatchItem in MatchesItens do
    begin
      BlocoItem := MatchItem.Groups[1].Value;
      FillChar(Item, SizeOf(Item), 0);
      Item.NumeroItem := Idx;
      Item.Descricao := ExtrairSpanPorClasse(BlocoItem, 'txtTit');
      if Item.Descricao.IsEmpty then
        Continue;

      TextoLimpo := ExtrairSpanPorClasse(BlocoItem, 'RCod');
      MatchAux := TRegEx.Match(TextoLimpo, '([A-Za-z0-9\-]+)\s*\)?$');
      if MatchAux.Success then
        Item.CodigoFornecedor := MatchAux.Groups[1].Value
      else
        Item.CodigoFornecedor := SomenteDigitos(TextoLimpo);

      if (Length(Item.CodigoFornecedor) in [8, 12, 13, 14]) and
         (SomenteDigitos(Item.CodigoFornecedor) = Item.CodigoFornecedor) then
        Item.EAN := Item.CodigoFornecedor;

      LinhaTxt := ExtrairSpanPorClasse(BlocoItem, 'Rqtd');
      Item.Quantidade := ParseNumero(LinhaTxt);
      if Item.Quantidade <= 0 then
        Item.Quantidade := 1;

      LinhaTxt := ExtrairSpanPorClasse(BlocoItem, 'RUN');
      LinhaTxt := TRegEx.Replace(LinhaTxt, '(?i)UN\s*:?', '').Trim;
      if LinhaTxt.IsEmpty then
        LinhaTxt := 'UN';
      Item.Unidade := UpperCase(Copy(LinhaTxt, 1, 10));

      LinhaTxt := ExtrairSpanPorClasse(BlocoItem, 'RvlUnit');
      Item.ValorUnitario := ParseNumero(LinhaTxt);

      LinhaTxt := ExtrairSpanPorClasse(BlocoItem, 'valor');
      Item.ValorTotal := ParseNumero(LinhaTxt);

      if (Item.ValorTotal <= 0) and (Item.ValorUnitario > 0) then
        Item.ValorTotal := RoundTo(Item.ValorUnitario * Item.Quantidade, -2);
      if (Item.ValorUnitario <= 0) and (Item.ValorTotal > 0) and (Item.Quantidade > 0) then
        Item.ValorUnitario := RoundTo(Item.ValorTotal / Item.Quantidade, -4);

      Lista.Add(Item);
      Inc(Idx);
    end;

    Result.Itens := Lista.ToArray;
  finally
    Lista.Free;
  end;

  // Totais da nota
  Result.ValorDesconto := ExtrairNumeroLinhaTabela('Descontos?\s*R\$\s*</[^>]+>\s*<span[^>]*>(.*?)</span>');
  Result.ValorTotal := ExtrairNumeroLinhaTabela('Valor\s+a\s+pagar\s*R\$\s*:?\s*</[^>]+>\s*<span[^>]*>(.*?)</span>');
  if Result.ValorTotal <= 0 then
    Result.ValorTotal := ExtrairNumeroLinhaTabela('Valor\s+total\s*R\$\s*:?\s*</[^>]+>\s*<span[^>]*>(.*?)</span>');

  if Result.ValorTotal <= 0 then
  begin
    for Item in Result.Itens do
      Result.ValorTotal := Result.ValorTotal + Item.ValorTotal;
    Result.ValorTotal := RoundTo(Max(0, Result.ValorTotal - Result.ValorDesconto), -2);
  end;

  // Forma de pagamento
  MatchAux := TRegEx.Match(Html, 'class\s*=\s*["''][^"'']*\btx\b[^"'']*["''][^>]*>(.*?)</', [roSingleLine, roIgnoreCase]);
  if MatchAux.Success then
  begin
    LinhaTxt := UpperCase(LimparHtml(MatchAux.Groups[1].Value));
    if LinhaTxt.Contains('PIX') then Result.FormaPagamento := 'PIX'
    else if LinhaTxt.Contains('CREDITO') or LinhaTxt.Contains('CRÉDITO') then Result.FormaPagamento := 'CARTAO CREDITO'
    else if LinhaTxt.Contains('DEBITO') or LinhaTxt.Contains('DÉBITO') then Result.FormaPagamento := 'CARTAO DEBITO'
    else if LinhaTxt.Contains('DINHEIRO') then Result.FormaPagamento := 'DINHEIRO'
    else if not LinhaTxt.IsEmpty then Result.FormaPagamento := Copy(LinhaTxt, 1, 20);
  end;
end;

class function TNFCeParserService.ParseFromUrl(const AUrl: string): TNFCeParsed;
var
  UrlLimpa, Html, RedirUrl: string;
  MatchMeta: TMatch;
begin
  UrlLimpa := Trim(AUrl);
  if UrlLimpa.IsEmpty then
    raise ENFCeParseException.Create('URL do QR Code da NFC-e e obrigatoria.');

  if not (UrlLimpa.ToLower.StartsWith('http://') or UrlLimpa.ToLower.StartsWith('https://')) then
    raise ENFCeParseException.Create('Link do QR Code invalido. Deve iniciar com http:// ou https://.');

  Html := BaixarHtmlUrl(UrlLimpa);

  // Segue redirect via meta-refresh caso a SEFAZ devolva pagina intermediaria
  MatchMeta := TRegEx.Match(Html, '<meta[^>]*http-equiv\s*=\s*["'']refresh["''][^>]*url\s*=\s*([^"''>\s]+)', [roIgnoreCase]);
  if MatchMeta.Success then
  begin
    RedirUrl := DecodificarEntidadesHtml(MatchMeta.Groups[1].Value);
    if RedirUrl.StartsWith('/') then
    begin
      MatchMeta := TRegEx.Match(UrlLimpa, '^(https?://[^/]+)', [roIgnoreCase]);
      if MatchMeta.Success then
        RedirUrl := MatchMeta.Groups[1].Value + RedirUrl;
    end;
    if RedirUrl.ToLower.StartsWith('http') then
      Html := BaixarHtmlUrl(RedirUrl);
  end;

  if DetectarCaptchaOuBloqueio(Html) then
    raise ENFCeCaptchaException.Create(
      'O portal da SEFAZ solicitou verificacao anti-bot/CAPTCHA para esta consulta. ' +
      'Exporte ou baixe o XML da NFC-e e use a opcao "Importar XML".'
    );

  Result := ParseFromHtml(Html, UrlLimpa);
  if Length(Result.Itens) = 0 then
    raise ENFCeParseException.Create(
      'Nao foi possivel extrair os itens da pagina retornada pela SEFAZ. ' +
      'Verifique o link ou utilize a opcao "Importar XML".'
    );
end;

class function TNFCeParserService.ParseFromXml(const AXml: string): TNFCeParsed;
var
  BlocoEmit, BlocoIde, BlocoTotal, BlocoPag, BlocoDet, BlocoProd: string;
  MatchesDet: TMatchCollection;
  MatchDet, MatchAux: TMatch;
  Lista: TList<TNFCeItemParsed>;
  Item: TNFCeItemParsed;
  Idx: Integer;
  DtAux: TDateTime;
  EAN: string;
begin
  if Trim(AXml).IsEmpty then
    raise ENFCeParseException.Create('Conteudo XML da NFC-e esta vazio.');

  FillChar(Result, SizeOf(Result), 0);
  Result.DataEmissao := Date;
  Result.FormaPagamento := 'DINHEIRO';

  MatchAux := TRegEx.Match(AXml, '<infNFe[^>]*Id\s*=\s*["'']NFe(\d{44})["'']', [roIgnoreCase]);
  if MatchAux.Success then
    Result.Chave := MatchAux.Groups[1].Value;

  BlocoIde := ExtrairTagXml(AXml, 'ide');
  if not BlocoIde.IsEmpty then
  begin
    Result.Numero := ExtrairTagXml(BlocoIde, 'nNF');
    Result.Serie := ExtrairTagXml(BlocoIde, 'serie');
    if ParseDataBR(ExtrairTagXml(BlocoIde, 'dhEmi'), DtAux) or
       ParseDataBR(ExtrairTagXml(BlocoIde, 'dEmi'), DtAux) then
      Result.DataEmissao := DtAux;
  end;

  BlocoEmit := ExtrairTagXml(AXml, 'emit');
  if not BlocoEmit.IsEmpty then
  begin
    Result.CnpjEmitente := SomenteDigitos(ExtrairTagXml(BlocoEmit, 'CNPJ'));
    if Result.CnpjEmitente.IsEmpty then
      Result.CnpjEmitente := SomenteDigitos(ExtrairTagXml(BlocoEmit, 'CPF'));
    Result.NomeEmitente := ExtrairTagXml(BlocoEmit, 'xFant');
    if Result.NomeEmitente.IsEmpty then
      Result.NomeEmitente := ExtrairTagXml(BlocoEmit, 'xNome');
  end;

  Lista := TList<TNFCeItemParsed>.Create;
  try
    MatchesDet := TRegEx.Matches(AXml, '<det(?:\s+[^>]*)?>(.*?)</det>', [roSingleLine, roIgnoreCase]);
    Idx := 1;
    for MatchDet in MatchesDet do
    begin
      BlocoDet := MatchDet.Groups[1].Value;
      BlocoProd := ExtrairTagXml(BlocoDet, 'prod');
      if BlocoProd.IsEmpty then
        BlocoProd := BlocoDet;

      FillChar(Item, SizeOf(Item), 0);
      Item.NumeroItem := Idx;
      Item.CodigoFornecedor := ExtrairTagXml(BlocoProd, 'cProd');
      EAN := SomenteDigitos(ExtrairTagXml(BlocoProd, 'cEAN'));
      if EAN.IsEmpty then
        EAN := SomenteDigitos(ExtrairTagXml(BlocoProd, 'cEANTrib'));
      if (Length(EAN) in [8, 12, 13, 14]) and (EAN <> '0000000000000') then
        Item.EAN := EAN;

      Item.Descricao := ExtrairTagXml(BlocoProd, 'xProd');
      Item.NCM := ExtrairTagXml(BlocoProd, 'NCM');
      Item.Unidade := UpperCase(Copy(ExtrairTagXml(BlocoProd, 'uCom'), 1, 10));
      if Item.Unidade.IsEmpty then
        Item.Unidade := 'UN';
      Item.Quantidade := ParseNumero(ExtrairTagXml(BlocoProd, 'qCom'));
      if Item.Quantidade <= 0 then
        Item.Quantidade := 1;
      Item.ValorUnitario := ParseNumero(ExtrairTagXml(BlocoProd, 'vUnCom'));
      Item.ValorTotal := ParseNumero(ExtrairTagXml(BlocoProd, 'vProd'));
      Item.Desconto := ParseNumero(ExtrairTagXml(BlocoProd, 'vDesc'));

      if (Item.ValorTotal <= 0) and (Item.ValorUnitario > 0) then
        Item.ValorTotal := RoundTo(Item.ValorUnitario * Item.Quantidade, -2);
      if (Item.ValorUnitario <= 0) and (Item.ValorTotal > 0) and (Item.Quantidade > 0) then
        Item.ValorUnitario := RoundTo(Item.ValorTotal / Item.Quantidade, -4);

      if not Item.Descricao.IsEmpty then
      begin
        Lista.Add(Item);
        Inc(Idx);
      end;
    end;
    Result.Itens := Lista.ToArray;
  finally
    Lista.Free;
  end;

  BlocoTotal := ExtrairTagXml(AXml, 'ICMSTot');
  if not BlocoTotal.IsEmpty then
  begin
    Result.ValorDesconto := ParseNumero(ExtrairTagXml(BlocoTotal, 'vDesc'));
    Result.ValorTotal := ParseNumero(ExtrairTagXml(BlocoTotal, 'vNF'));
  end;

  if Result.ValorTotal <= 0 then
  begin
    for Item in Result.Itens do
      Result.ValorTotal := Result.ValorTotal + Item.ValorTotal - Item.Desconto;
    Result.ValorTotal := RoundTo(Max(0, Result.ValorTotal), -2);
  end;

  BlocoPag := ExtrairTagXml(AXml, 'detPag');
  if not BlocoPag.IsEmpty then
    Result.FormaPagamento := MapearPagamentoXML(ExtrairTagXml(BlocoPag, 'tPag'));

  if Length(Result.Itens) = 0 then
    raise ENFCeParseException.Create('Nenhum item encontrado no XML informado.');
end;

end.
