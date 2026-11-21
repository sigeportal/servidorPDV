unit NFCe.Controller;

interface

uses
  Horse,
  Horse.Commons,
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

type
  TNFCeController = class
  private
    class function SuccessResponse(AData: TJSONValue; const AMessage: string = ''): TJSONObject; static;
    class function ErrorResponse(const AMessage, ACode: string; const ADetails: string = ''): TJSONObject; static;
    class function SomenteDigitos(const Texto: string): string; static;
    class function FormatarCNPJ(const Digitos: string): string; static;
    class function ParseIsoOuBrData(const Texto: string): TDateTime; static;
    class function ObterCaixa(Conn: TFDConnection; Trans: TFDTransaction; PDV: Integer): Integer; static;
    class function ObterFuncionarioValido(Conn: TFDConnection; Trans: TFDTransaction; CodFun: Integer): Integer; static;
    class function ObterGrupoPadrao(Conn: TFDConnection; Trans: TFDTransaction; GrupoInformado: Integer): Integer; static;
    class function ObterFornecedorPorCNPJ(Conn: TFDConnection; Trans: TFDTransaction; const CNPJ: string): Integer; static;
    class function ObterOuCriarFornecedor(Conn: TFDConnection; Trans: TFDTransaction; const CNPJ, NomeEmitente: string): Integer; static;
    class function ProximoGen(Conn: TFDConnection; Trans: TFDTransaction; const NomeGen: string): Integer; static;
    class function ProximoCodigo(Conn: TFDConnection; Trans: TFDTransaction; const Tabela, Campo: string): Integer; static;
    class procedure InserirMovimentacao(Conn: TFDConnection; Trans: TFDTransaction; Codigo: Integer; Credito, Debito: Currency; const Descricao, Plano, Nome: string; Conta, Caixa: Integer; Estado: string = 'A'); static;
    class procedure UpsertMapaFornecedor(Conn: TFDConnection; Trans: TFDTransaction; const CnpjForn, CodFornItem, EAN, NomeNF, Destino, UnidadeNF: string; ProCodigo, SubDespesa: Integer; FatorConv: Double); static;
  public
    class procedure Registrar;
    class procedure Parse(Req: THorseRequest; Res: THorseResponse);
    class procedure Confirmar(Req: THorseRequest; Res: THorseResponse);
    class procedure Historico(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils,
  System.Generics.Collections,
  Data.DB,
  UnitConnection.Model.Interfaces,
  UnitDatabase,
  UnitProducao.Service,
  UnitNFCeParser.Service;

{ TNFCeController }

class function TNFCeController.SuccessResponse(AData: TJSONValue; const AMessage: string): TJSONObject;
var
  Meta: TJSONObject;
begin
  Result := TJSONObject.Create;
  Meta := TJSONObject.Create;
  Meta.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));

  Result.AddPair('success', TJSONBool.Create(True));
  Result.AddPair('message', AMessage);
  if Assigned(AData) then
    Result.AddPair('data', AData)
  else
    Result.AddPair('data', TJSONNull.Create);
  Result.AddPair('meta', Meta);
end;

class function TNFCeController.ErrorResponse(const AMessage, ACode, ADetails: string): TJSONObject;
var
  ErrorObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  ErrorObj := TJSONObject.Create;
  ErrorObj.AddPair('code', ACode);
  if not ADetails.IsEmpty then
    ErrorObj.AddPair('details', ADetails)
  else
    ErrorObj.AddPair('details', TJSONNull.Create);
  ErrorObj.AddPair('fields', TJSONArray.Create);

  Result.AddPair('success', TJSONBool.Create(False));
  Result.AddPair('message', AMessage);
  Result.AddPair('error', ErrorObj);
end;

class function TNFCeController.SomenteDigitos(const Texto: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in Texto do
    if CharInSet(Ch, ['0'..'9']) then
      Result := Result + Ch;
end;

class function TNFCeController.FormatarCNPJ(const Digitos: string): string;
var
  D: string;
begin
  D := SomenteDigitos(Digitos);
  if Length(D) = 14 then
    Result := Copy(D, 1, 2) + '.' + Copy(D, 3, 3) + '.' + Copy(D, 6, 3) + '/' + Copy(D, 9, 4) + '-' + Copy(D, 13, 2)
  else
    Result := Copy(D, 1, 18);
end;

class function TNFCeController.ParseIsoOuBrData(const Texto: string): TDateTime;
var
  S: string;
  A, M, D: Word;
begin
  Result := Date;
  S := Trim(Texto);
  if S.IsEmpty then
    Exit;
  if (Length(S) >= 10) and (S[5] = '-') and (S[8] = '-') then
  begin
    A := StrToIntDef(Copy(S, 1, 4), 0);
    M := StrToIntDef(Copy(S, 6, 2), 0);
    D := StrToIntDef(Copy(S, 9, 2), 0);
    if not TryEncodeDate(A, M, D, Result) then
      Result := Date;
  end
  else if (Length(S) >= 10) and (S[3] = '/') and (S[6] = '/') then
  begin
    D := StrToIntDef(Copy(S, 1, 2), 0);
    M := StrToIntDef(Copy(S, 4, 2), 0);
    A := StrToIntDef(Copy(S, 7, 4), 0);
    if not TryEncodeDate(A, M, D, Result) then
      Result := Date;
  end;
end;

class function TNFCeController.ProximoGen(Conn: TFDConnection; Trans: TFDTransaction; const NomeGen: string): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text := 'SELECT GEN_ID(' + UpperCase(Trim(NomeGen)) + ', 1) AS ID FROM RDB$DATABASE';
    Q.Open;
    Result := Q.FieldByName('ID').AsInteger;
  finally
    Q.DisposeOf;
  end;
end;

class function TNFCeController.ProximoCodigo(Conn: TFDConnection; Trans: TFDTransaction; const Tabela, Campo: string): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text := 'SELECT COALESCE(MAX(' + Campo + '), 0) + 1 AS PROX FROM ' + Tabela;
    Q.Open;
    Result := Q.FieldByName('PROX').AsInteger;
  finally
    Q.DisposeOf;
  end;
end;

class function TNFCeController.ObterCaixa(Conn: TFDConnection; Trans: TFDTransaction; PDV: Integer): Integer;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    if PDV > 0 then
    begin
      Q.SQL.Text :=
        'SELECT FIRST 1 CAI_CODIGO FROM CAIXA ' +
        'WHERE CAI_PDV = :PDV ' +
        'ORDER BY CAI_CODIGO DESC';
      Q.ParamByName('PDV').AsInteger := PDV;
    end
    else
      Q.SQL.Text :=
        'SELECT FIRST 1 CAI_CODIGO FROM CAIXA ' +
        'ORDER BY CAI_CODIGO DESC';
    Q.Open;
    if not Q.IsEmpty then
      Result := Q.FieldByName('CAI_CODIGO').AsInteger;
  finally
    Q.DisposeOf;
  end;
end;

class function TNFCeController.ObterFuncionarioValido(Conn: TFDConnection; Trans: TFDTransaction; CodFun: Integer): Integer;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    if CodFun > 0 then
    begin
      Q.SQL.Text := 'SELECT FIRST 1 FUN_CODIGO FROM FUNCIONARIOS WHERE FUN_CODIGO = :FUN';
      Q.ParamByName('FUN').AsInteger := CodFun;
      Q.Open;
      if not Q.IsEmpty then
        Exit(Q.FieldByName('FUN_CODIGO').AsInteger);
    end;
    Q.Close;
    Q.SQL.Text := 'SELECT FIRST 1 FUN_CODIGO FROM FUNCIONARIOS ORDER BY FUN_CODIGO';
    Q.Open;
    if not Q.IsEmpty then
      Result := Q.FieldByName('FUN_CODIGO').AsInteger;
  finally
    Q.DisposeOf;
  end;
end;

class function TNFCeController.ObterGrupoPadrao(Conn: TFDConnection; Trans: TFDTransaction; GrupoInformado: Integer): Integer;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    if GrupoInformado > 0 then
    begin
      Q.SQL.Text := 'SELECT FIRST 1 GRU_CODIGO FROM GRUPOS WHERE GRU_CODIGO = :GRU';
      Q.ParamByName('GRU').AsInteger := GrupoInformado;
      Q.Open;
      if not Q.IsEmpty then
        Exit(Q.FieldByName('GRU_CODIGO').AsInteger);
    end;
    Q.Close;
    Q.SQL.Text := 'SELECT FIRST 1 GRU_CODIGO FROM GRUPOS ORDER BY GRU_CODIGO';
    Q.Open;
    if not Q.IsEmpty then
      Result := Q.FieldByName('GRU_CODIGO').AsInteger;
  finally
    Q.DisposeOf;
  end;
end;

class function TNFCeController.ObterFornecedorPorCNPJ(Conn: TFDConnection; Trans: TFDTransaction; const CNPJ: string): Integer;
var
  Q: TFDQuery;
  AlvoDig: string;
begin
  Result := 0;
  AlvoDig := SomenteDigitos(CNPJ);
  if AlvoDig.IsEmpty then
    Exit;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text := 'SELECT FOR_CODIGO, FOR_CNPJ_CPF FROM FORNECEDORES WHERE FOR_CNPJ_CPF IS NOT NULL';
    Q.Open;
    while not Q.Eof do
    begin
      if SomenteDigitos(Q.FieldByName('FOR_CNPJ_CPF').AsString) = AlvoDig then
        Exit(Q.FieldByName('FOR_CODIGO').AsInteger);
      Q.Next;
    end;
  finally
    Q.DisposeOf;
  end;
end;

class function TNFCeController.ObterOuCriarFornecedor(Conn: TFDConnection; Trans: TFDTransaction; const CNPJ, NomeEmitente: string): Integer;
var
  Q: TFDQuery;
  CnpjDig, CnpjFmt, NomeLimpo: string;
begin
  CnpjDig := SomenteDigitos(CNPJ);
  Result := ObterFornecedorPorCNPJ(Conn, Trans, CnpjDig);
  if Result > 0 then
    Exit;

  NomeLimpo := UpperCase(Trim(NomeEmitente));
  if NomeLimpo.IsEmpty then
    NomeLimpo := 'FORNECEDOR NFCE';

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Result := ProximoCodigo(Conn, Trans, 'FORNECEDORES', 'FOR_CODIGO');
    CnpjFmt := FormatarCNPJ(CnpjDig);

    Q.SQL.Text :=
      'INSERT INTO FORNECEDORES (' +
      '  FOR_CODIGO, FOR_NOME, FOR_CNPJ_CPF, FOR_RAZAO_SOCIAL, FOR_FANTASIA, FOR_TIPO, FOR_DATAC' +
      ') VALUES (' +
      '  :CODIGO, :NOME, :CNPJ, :RAZAO, :FANTASIA, ''JURIDICA'', CURRENT_DATE' +
      ')';
    Q.ParamByName('CODIGO').AsInteger := Result;
    Q.ParamByName('NOME').AsString := Copy(NomeLimpo, 1, 80);
    Q.ParamByName('CNPJ').AsString := CnpjFmt;
    Q.ParamByName('RAZAO').AsString := Copy(NomeLimpo, 1, 100);
    Q.ParamByName('FANTASIA').AsString := Copy(NomeLimpo, 1, 100);
    Q.ExecSQL;
  finally
    Q.DisposeOf;
  end;
end;

class procedure TNFCeController.InserirMovimentacao(Conn: TFDConnection; Trans: TFDTransaction; Codigo: Integer; Credito, Debito: Currency; const Descricao, Plano, Nome: string; Conta, Caixa: Integer; Estado: string);
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Add('INSERT INTO MOVIMENTACOES (');
    Q.SQL.Add('  MOV_CODIGO, MOV_CREDITO, MOV_DEBITO, MOV_DESCRICAO, MOV_TIPO, MOV_DATA, MOV_CON,');
    Q.SQL.Add('  MOV_DATAHORA, MOV_ORDENA, MOV_PLANO, MOV_NOME, MOV_CAI, MOV_ESTADO, MOV_TROCO');
    Q.SQL.Add(') VALUES (');
    Q.SQL.Add('  :CODIGO, :CREDITO, :DEBITO, :DESCRICAO, :TIPO, CURRENT_DATE, :CONTA,');
    Q.SQL.Add('  CURRENT_TIMESTAMP, :ORDENA, :PLANO, :NOME, :CAIXA, :ESTADO, 0');
    Q.SQL.Add(')');
    Q.ParamByName('CODIGO').AsInteger := Codigo;
    Q.ParamByName('CREDITO').AsCurrency := Credito;
    Q.ParamByName('DEBITO').AsCurrency := Debito;
    Q.ParamByName('DESCRICAO').AsString := Copy(Trim(Descricao), 1, 30);
    Q.ParamByName('TIPO').AsInteger := 2;
    Q.ParamByName('CONTA').AsInteger := Conta;
    Q.ParamByName('ORDENA').AsInteger := Codigo;
    Q.ParamByName('PLANO').AsString := Copy(Plano, 1, 15);
    Q.ParamByName('NOME').AsString := Copy(Trim(Nome), 1, 30);
    Q.ParamByName('CAIXA').AsInteger := Caixa;
    Q.ParamByName('ESTADO').AsString := Copy(Estado, 1, 1);
    Q.ExecSQL;

    Q.SQL.Clear;
    if Conta = 0 then
    begin
      if Caixa > 0 then
      begin
        Q.SQL.Add('UPDATE CAIXA SET CAI_VALORD = COALESCE(CAI_VALORD, 0) + :CREDITO - :DEBITO');
        Q.SQL.Add('WHERE CAI_CODIGO = :CODIGO');
        Q.ParamByName('CODIGO').AsInteger := Caixa;
        Q.ParamByName('CREDITO').AsCurrency := Credito;
        Q.ParamByName('DEBITO').AsCurrency := Debito;
        Q.ExecSQL;
      end;
    end
    else
    begin
      Q.SQL.Add('UPDATE CONTAS SET CON_SALDO = COALESCE(CON_SALDO, 0) + :CREDITO - :DEBITO');
      Q.SQL.Add('WHERE CON_CODIGO = :CODIGO');
      Q.ParamByName('CODIGO').AsInteger := Conta;
      Q.ParamByName('CREDITO').AsCurrency := Credito;
      Q.ParamByName('DEBITO').AsCurrency := Debito;
      Q.ExecSQL;
    end;
  finally
    Q.DisposeOf;
  end;
end;

class procedure TNFCeController.UpsertMapaFornecedor(Conn: TFDConnection; Trans: TFDTransaction; const CnpjForn, CodFornItem, EAN, NomeNF, Destino, UnidadeNF: string; ProCodigo, SubDespesa: Integer; FatorConv: Double);
var
  Q: TFDQuery;
  CnpjLimpo, CodLimpo, EanLimpo: string;
  CodMapa: Integer;
begin
  CnpjLimpo := Copy(SomenteDigitos(CnpjForn), 1, 20);
  CodLimpo := Copy(Trim(CodFornItem), 1, 60);
  EanLimpo := Copy(Trim(EAN), 1, 20);
  if CnpjLimpo.IsEmpty or (CodLimpo.IsEmpty and EanLimpo.IsEmpty) then
    Exit;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Add('SELECT FIRST 1 PFM_CODIGO FROM PROD_FORN_MAP');
    Q.SQL.Add('WHERE PFM_CNPJ_FORN = :CNPJ');
    if (not CodLimpo.IsEmpty) and (not EanLimpo.IsEmpty) then
    begin
      Q.SQL.Add('  AND (PFM_COD_FORN_ITEM = :COD OR PFM_EAN = :EAN)');
      Q.ParamByName('COD').AsString := CodLimpo;
      Q.ParamByName('EAN').AsString := EanLimpo;
    end
    else if not CodLimpo.IsEmpty then
    begin
      Q.SQL.Add('  AND PFM_COD_FORN_ITEM = :COD');
      Q.ParamByName('COD').AsString := CodLimpo;
    end
    else
    begin
      Q.SQL.Add('  AND PFM_EAN = :EAN');
      Q.ParamByName('EAN').AsString := EanLimpo;
    end;
    Q.ParamByName('CNPJ').AsString := CnpjLimpo;
    Q.Open;

    if not Q.IsEmpty then
    begin
      CodMapa := Q.FieldByName('PFM_CODIGO').AsInteger;
      Q.Close;
      Q.SQL.Text :=
        'UPDATE PROD_FORN_MAP SET ' +
        '  PFM_EAN = :EAN, PFM_NOME_NF = :NOME, PFM_PRO = :PRO, ' +
        '  PFM_DESTINO = :DESTINO, PFM_FATOR_CONV = :FATOR, PFM_UNIDADE_NF = :UNID, ' +
        '  PFM_SUD = :SUD, PFM_DATAU = CURRENT_TIMESTAMP ' +
        'WHERE PFM_CODIGO = :CODIGO';
      Q.ParamByName('CODIGO').AsInteger := CodMapa;
    end
    else
    begin
      CodMapa := ProximoGen(Conn, Trans, 'GEN_PFM');
      Q.Close;
      Q.SQL.Text :=
        'INSERT INTO PROD_FORN_MAP (' +
        '  PFM_CODIGO, PFM_CNPJ_FORN, PFM_COD_FORN_ITEM, PFM_EAN, PFM_NOME_NF, ' +
        '  PFM_PRO, PFM_DESTINO, PFM_FATOR_CONV, PFM_UNIDADE_NF, PFM_SUD, PFM_DATAU' +
        ') VALUES (' +
        '  :CODIGO, :CNPJ, :CODITEM, :EAN, :NOME, :PRO, :DESTINO, :FATOR, :UNID, :SUD, CURRENT_TIMESTAMP' +
        ')';
      Q.ParamByName('CODIGO').AsInteger := CodMapa;
      Q.ParamByName('CNPJ').AsString := Copy(CnpjLimpo, 1, 20);
      Q.ParamByName('CODITEM').AsString := Copy(CodLimpo, 1, 60);
    end;

    Q.ParamByName('EAN').AsString := Copy(Trim(EAN), 1, 20);
    Q.ParamByName('NOME').AsString := Copy(Trim(NomeNF), 1, 150);
    Q.ParamByName('PRO').AsInteger := ProCodigo;
    Q.ParamByName('DESTINO').AsString := Copy(UpperCase(Trim(Destino)), 1, 15);
    Q.ParamByName('FATOR').AsFloat := Max(0.0001, FatorConv);
    Q.ParamByName('UNID').AsString := Copy(UpperCase(Trim(UnidadeNF)), 1, 10);
    Q.ParamByName('SUD').AsInteger := SubDespesa;
    Q.ExecSQL;
  finally
    Q.DisposeOf;
  end;
end;

class procedure TNFCeController.Parse(Req: THorseRequest; Res: THorseResponse);
var
  Body: TJSONObject;
  Url, Xml: string;
  Nota: TNFCeParsed;
  Query: iQuery;
  DataObj, NotaObj, ItemObj, SugObj: TJSONObject;
  ItensArr: TJSONArray;
  Item: TNFCeItemParsed;
  JaImportada: Boolean;
  CodFornBanco, ProCod, SubDesp, SubDespSugCod: Integer;
  ProNome, ProTipo, ProUnid, OrigemMatch, DestinoSug, CodLimpo, EanLimpo: string;
  ModoSugerido, SubDespSugNome: string;
  FatorSug: Double;
begin
  TProducaoService.GarantirEstrutura;
  try
    Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if not Assigned(Body) then
    begin
      Res.Status(THTTPStatus.BadRequest)
        .Send<TJSONObject>(ErrorResponse('Corpo da requisicao invalido.', 'VALIDATION_ERROR'));
      Exit;
    end;

    try
      Url := '';
      Xml := '';
      Body.TryGetValue<string>('url', Url);
      Body.TryGetValue<string>('xml', Xml);

      if not Trim(Xml).IsEmpty then
        Nota := TNFCeParserService.ParseFromXml(Xml)
      else if not Trim(Url).IsEmpty then
        Nota := TNFCeParserService.ParseFromUrl(Url)
      else
      begin
        Res.Status(THTTPStatus.BadRequest)
          .Send<TJSONObject>(ErrorResponse('Informe o link do QR Code (url) ou o XML da NFC-e.', 'VALIDATION_ERROR'));
        Exit;
      end;

      Query := TDatabase.Query;

      // Verifica duplicidade em NFCE_IMPORTACOES
      JaImportada := False;
      if not Nota.Chave.IsEmpty then
      begin
        Query.Clear;
        Query.Add('SELECT FIRST 1 NI_CODIGO, NI_DATA_IMPORT FROM NFCE_IMPORTACOES WHERE NI_CHAVE = :CHAVE');
        Query.AddParam('CHAVE', Nota.Chave);
        Query.Open;
        JaImportada := not Query.DataSet.IsEmpty;
      end;

      // Verifica se o fornecedor ja existe pelo CNPJ
      CodFornBanco := 0;
      if not Nota.CnpjEmitente.IsEmpty then
      begin
        Query.Clear;
        Query.Add('SELECT FOR_CODIGO, FOR_CNPJ_CPF FROM FORNECEDORES WHERE FOR_CNPJ_CPF IS NOT NULL');
        Query.Open;
        Query.DataSet.First;
        while not Query.DataSet.Eof do
        begin
          if SomenteDigitos(Query.DataSet.FieldByName('FOR_CNPJ_CPF').AsString) = Nota.CnpjEmitente then
          begin
            CodFornBanco := Query.DataSet.FieldByName('FOR_CODIGO').AsInteger;
            Break;
          end;
          Query.DataSet.Next;
        end;
      end;

      // Sugere modo e subdespesa conforme ultimo lancamento deste fornecedor
      ModoSugerido := 'COMPRA';
      SubDespSugCod := 0;
      SubDespSugNome := '';
      if not Nota.CnpjEmitente.IsEmpty then
      begin
        Query.Clear;
        Query.Add('SELECT FIRST 1 NI_MODO');
        Query.Add('FROM NFCE_IMPORTACOES');
        Query.Add('WHERE NI_CNPJ_EMIT = :CNPJ');
        Query.Add('ORDER BY NI_CODIGO DESC');
        Query.AddParam('CNPJ', Nota.CnpjEmitente);
        Query.Open;
        if (not Query.DataSet.IsEmpty) and
           (UpperCase(Trim(Query.DataSet.FieldByName('NI_MODO').AsString)) = 'DESPESA') then
          ModoSugerido := 'DESPESA';

        Query.Clear;
        Query.Add('SELECT FIRST 1 C.CUST_SUD, COALESCE(S.SUD_NOME, '''') SUD_NOME');
        Query.Add('FROM NFCE_IMPORTACOES N');
        Query.Add('JOIN CUSTOS C ON C.CUST_CODIGO = N.NI_CUST_CODIGO');
        Query.Add('LEFT JOIN SUB_DES S ON S.SUD_CODIGO = C.CUST_SUD');
        Query.Add('WHERE N.NI_CNPJ_EMIT = :CNPJ');
        Query.Add('  AND COALESCE(N.NI_CUST_CODIGO, 0) > 0');
        Query.Add('  AND COALESCE(C.CUST_SUD, 0) > 0');
        Query.Add('ORDER BY N.NI_CODIGO DESC');
        Query.AddParam('CNPJ', Nota.CnpjEmitente);
        Query.Open;
        if not Query.DataSet.IsEmpty then
        begin
          SubDespSugCod := Query.DataSet.FieldByName('CUST_SUD').AsInteger;
          SubDespSugNome := Trim(Query.DataSet.FieldByName('SUD_NOME').AsString);
        end;
      end;

      NotaObj := TJSONObject.Create;
      NotaObj.AddPair('chave', Nota.Chave);
      NotaObj.AddPair('url', Nota.Url);
      NotaObj.AddPair('numero', Nota.Numero);
      NotaObj.AddPair('serie', Nota.Serie);
      NotaObj.AddPair('data_emissao', FormatDateTime('yyyy-mm-dd', Nota.DataEmissao));
      NotaObj.AddPair('cnpj_emitente', Nota.CnpjEmitente);
      NotaObj.AddPair('cnpj_formatado', FormatarCNPJ(Nota.CnpjEmitente));
      NotaObj.AddPair('nome_emitente', Nota.NomeEmitente);
      NotaObj.AddPair('fornecedor_codigo', TJSONNumber.Create(CodFornBanco));
      NotaObj.AddPair('valor_total', TJSONNumber.Create(RoundTo(Nota.ValorTotal, -2)));
      NotaObj.AddPair('valor_desconto', TJSONNumber.Create(RoundTo(Nota.ValorDesconto, -2)));
      NotaObj.AddPair('forma_pagamento', Nota.FormaPagamento);
      NotaObj.AddPair('ja_importada', TJSONBool.Create(JaImportada));
      NotaObj.AddPair('modo_sugerido', ModoSugerido);
      NotaObj.AddPair('subdespesa_sugerida_codigo', TJSONNumber.Create(SubDespSugCod));
      NotaObj.AddPair('subdespesa_sugerida_nome', SubDespSugNome);

      ItensArr := TJSONArray.Create;
      for Item in Nota.Itens do
      begin
        OrigemMatch := 'NENHUM';
        DestinoSug := 'COMPRA';
        ProCod := 0;
        ProNome := '';
        ProTipo := '';
        ProUnid := '';
        FatorSug := 1.0;
        SubDesp := 0;

        // 1) Busca no historico de vinculos do fornecedor (PROD_FORN_MAP)
        CodLimpo := Copy(Trim(Item.CodigoFornecedor), 1, 60);
        EanLimpo := Copy(Trim(Item.EAN), 1, 20);
        if (not Nota.CnpjEmitente.IsEmpty) and ((not CodLimpo.IsEmpty) or (not EanLimpo.IsEmpty)) then
        begin
          Query.Clear;
          Query.Add('SELECT FIRST 1 M.PFM_PRO, M.PFM_DESTINO, COALESCE(M.PFM_FATOR_CONV, 1) PFM_FATOR_CONV, COALESCE(M.PFM_SUD, 0) PFM_SUD,');
          Query.Add('       P.PRO_NOME, COALESCE(P.PRO_TIPO, '''') PRO_TIPO, COALESCE(P.PRO_EMBALAGEM, '''') PRO_EMBALAGEM');
          Query.Add('FROM PROD_FORN_MAP M');
          Query.Add('LEFT JOIN PRODUTOS P ON P.PRO_CODIGO = M.PFM_PRO');
          Query.Add('WHERE M.PFM_CNPJ_FORN = :CNPJ');
          if (not CodLimpo.IsEmpty) and (not EanLimpo.IsEmpty) then
          begin
            Query.Add('  AND (M.PFM_COD_FORN_ITEM = :COD OR M.PFM_EAN = :EAN)');
            Query.Add('ORDER BY M.PFM_DATAU DESC');
            Query.AddParam('CNPJ', Nota.CnpjEmitente);
            Query.AddParam('COD', CodLimpo);
            Query.AddParam('EAN', EanLimpo);
          end
          else if not CodLimpo.IsEmpty then
          begin
            Query.Add('  AND M.PFM_COD_FORN_ITEM = :COD');
            Query.Add('ORDER BY M.PFM_DATAU DESC');
            Query.AddParam('CNPJ', Nota.CnpjEmitente);
            Query.AddParam('COD', CodLimpo);
          end
          else
          begin
            Query.Add('  AND M.PFM_EAN = :EAN');
            Query.Add('ORDER BY M.PFM_DATAU DESC');
            Query.AddParam('CNPJ', Nota.CnpjEmitente);
            Query.AddParam('EAN', EanLimpo);
          end;
          Query.Open;

          if not Query.DataSet.IsEmpty then
          begin
            OrigemMatch := 'HISTORICO';
            ProCod := Query.DataSet.FieldByName('PFM_PRO').AsInteger;
            DestinoSug := Query.DataSet.FieldByName('PFM_DESTINO').AsString;
            if DestinoSug.IsEmpty then DestinoSug := 'COMPRA';
            FatorSug := Query.DataSet.FieldByName('PFM_FATOR_CONV').AsFloat;
            if FatorSug <= 0 then FatorSug := 1.0;
            SubDesp := Query.DataSet.FieldByName('PFM_SUD').AsInteger;
            if ProCod > 0 then
            begin
              ProNome := Query.DataSet.FieldByName('PRO_NOME').AsString;
              ProTipo := TProducaoService.NormalizarTipoProduto(Query.DataSet.FieldByName('PRO_TIPO').AsString);
              ProUnid := TProducaoService.NormalizarUnidade(Query.DataSet.FieldByName('PRO_EMBALAGEM').AsString);
            end;
          end;
        end;

        // 2) Se nao encontrou no historico, tenta match por EAN / codigo de barras
        if (ProCod = 0) and (not Item.EAN.IsEmpty) then
        begin
          Query.Clear;
          Query.Add('SELECT FIRST 1 PRO_CODIGO, PRO_NOME, COALESCE(PRO_TIPO, '''') PRO_TIPO, COALESCE(PRO_EMBALAGEM, '''') PRO_EMBALAGEM');
          Query.Add('FROM PRODUTOS');
          Query.Add('WHERE PRO_CODBARRA = :EAN OR PRO_GTIN = :GTIN');
          Query.AddParam('EAN', Copy(Item.EAN, 1, 30));
          Query.AddParam('GTIN', Copy(Item.EAN, 1, 14));
          Query.Open;
          if not Query.DataSet.IsEmpty then
          begin
            OrigemMatch := 'EAN';
            ProCod := Query.DataSet.FieldByName('PRO_CODIGO').AsInteger;
            ProNome := Query.DataSet.FieldByName('PRO_NOME').AsString;
            ProTipo := TProducaoService.NormalizarTipoProduto(Query.DataSet.FieldByName('PRO_TIPO').AsString);
            ProUnid := TProducaoService.NormalizarUnidade(Query.DataSet.FieldByName('PRO_EMBALAGEM').AsString);
            FatorSug := TProducaoService.CalcularFatorConversao(Item.Unidade, ProUnid);
          end;
        end;

        SugObj := TJSONObject.Create;
        SugObj.AddPair('origem_match', OrigemMatch);
        SugObj.AddPair('destino', DestinoSug);
        SugObj.AddPair('pro_codigo', TJSONNumber.Create(ProCod));
        SugObj.AddPair('pro_nome', ProNome);
        SugObj.AddPair('pro_tipo', ProTipo);
        SugObj.AddPair('pro_unidade', ProUnid);
        SugObj.AddPair('fator_conversao', TJSONNumber.Create(RoundTo(FatorSug, -4)));
        SugObj.AddPair('subdespesa_codigo', TJSONNumber.Create(SubDesp));

        ItemObj := TJSONObject.Create;
        ItemObj.AddPair('numero_item', TJSONNumber.Create(Item.NumeroItem));
        ItemObj.AddPair('codigo_fornecedor', Item.CodigoFornecedor);
        ItemObj.AddPair('ean', Item.EAN);
        ItemObj.AddPair('descricao', Item.Descricao);
        ItemObj.AddPair('unidade', Item.Unidade);
        ItemObj.AddPair('quantidade', TJSONNumber.Create(RoundTo(Item.Quantidade, -4)));
        ItemObj.AddPair('valor_unitario', TJSONNumber.Create(RoundTo(Item.ValorUnitario, -4)));
        ItemObj.AddPair('valor_total', TJSONNumber.Create(RoundTo(Item.ValorTotal, -2)));
        ItemObj.AddPair('desconto', TJSONNumber.Create(RoundTo(Item.Desconto, -2)));
        ItemObj.AddPair('ncm', Item.NCM);
        ItemObj.AddPair('sugestao', SugObj);
        ItensArr.AddElement(ItemObj);
      end;

      NotaObj.AddPair('itens', ItensArr);
      DataObj := NotaObj;
      Res.Status(THTTPStatus.OK).Send<TJSONObject>(SuccessResponse(DataObj, 'NFC-e lida com sucesso.'));
    finally
      Body.Free;
    end;
  except
    on E: ENFCeCaptchaException do
      Res.Status(422).Send<TJSONObject>(ErrorResponse(E.Message, 'CAPTCHA_REQUIRED'));
    on E: ENFCeParseException do
      Res.Status(422).Send<TJSONObject>(ErrorResponse(E.Message, 'PARSE_ERROR'));
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError)
        .Send<TJSONObject>(ErrorResponse('Falha ao processar NFC-e.', 'INTERNAL_ERROR', E.Message));
  end;
end;

class procedure TNFCeController.Confirmar(Req: THorseRequest; Res: THorseResponse);
var
  Body, ItemObj, RespObj: TJSONObject;
  ItensArr: TJSONArray;
  RecalculadasArr: TJSONArray;
  I: Integer;
  Chave, Url, Numero, Serie, DataStr, CnpjEmit, NomeEmit, Modo, CondicaoPgto, FormaPgto: string;
  DataVencStr, SubDespNome, DescricaoItem, UnidNF, CodFornItem, EAN, DestinoItem: string;
  NovoNome, NovoTipo, NovoUnid, OrigemHis, DocHis, HistoricoCusto, HistoricoDespesa, ObsDespesa: string;
  DataEmissao, DataVencimento: TDateTime;
  ValorTotalNota, ValorDescNota: Double;
  Conta, PDV, Funcionario, SubDespesa: Integer;
  PermitirDuplicada, CriarProduto, TemItemCompra: Boolean;
  QtdNF, VlrUnitNF, VlrTotalItem, FatorConv, QtdEstoque, CustoUnitEst: Double;
  NovoValorV, NovoCM, NovoEst, TotalCompraPrevisto, VlrCompraCab: Double;
  ProCodigo, GrupoPro, UmCod: Integer;
  TotalCompra, TotalDespesaItens, TotalLancamentoDespesa: Double;
  QtdItensEstoque, QtdItensDespesa: Integer;
  CodForn, CodImportacao, CodCompra, CodCusto, CodFat2, CodPag, CodMov, CodPP, CodCaixa, CodCE: Integer;
  TemTabelaCompras, TemTabelaComEst: Boolean;
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Transacao: TFDTransaction;
  Q: TFDQuery;
begin
  TProducaoService.GarantirEstrutura;
  Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
  if not Assigned(Body) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Corpo da requisicao invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;

  BancoDados := TDatabase.Connection;
  IndiceConexao := BancoDados.Connected;
  Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
  Transacao := TFDTransaction.Create(nil);
  try
    try
      Transacao.Connection := Conexao;
      Transacao.Options.Params.Clear;
      Transacao.Options.Params.Add('write');
      Transacao.Options.Params.Add('read_committed');
      Transacao.Options.Params.Add('rec_version');
      Transacao.Options.Params.Add('nowait');

      Chave := ''; Body.TryGetValue<string>('chave', Chave); Chave := Trim(Chave);
      Url := ''; Body.TryGetValue<string>('url', Url);
      Numero := ''; Body.TryGetValue<string>('numero', Numero);
      Serie := ''; Body.TryGetValue<string>('serie', Serie);
      DataStr := ''; Body.TryGetValue<string>('data_emissao', DataStr);
      DataEmissao := ParseIsoOuBrData(DataStr);
      CnpjEmit := ''; Body.TryGetValue<string>('cnpj_emitente', CnpjEmit); CnpjEmit := SomenteDigitos(CnpjEmit);
      NomeEmit := ''; Body.TryGetValue<string>('nome_emitente', NomeEmit);
      ValorTotalNota := 0; Body.TryGetValue<Double>('valor_total', ValorTotalNota);
      ValorDescNota := 0; Body.TryGetValue<Double>('valor_desconto', ValorDescNota);
      Modo := 'COMPRA';
      if Body.TryGetValue<string>('modo', Modo) then
        Modo := UpperCase(Trim(Modo));
      if (Modo <> 'COMPRA') and (Modo <> 'DESPESA') then
        Modo := 'COMPRA';

      CondicaoPgto := 'V';
      if Body.TryGetValue<string>('condicao_pgto', CondicaoPgto) then
        CondicaoPgto := UpperCase(Trim(CondicaoPgto));
      if (CondicaoPgto <> 'V') and (CondicaoPgto <> 'P') then
        CondicaoPgto := 'V';

      DataVencStr := ''; Body.TryGetValue<string>('data_vencimento', DataVencStr);
      DataVencimento := ParseIsoOuBrData(DataVencStr);
      if (CondicaoPgto = 'P') and (DataVencimento < Date) then
        DataVencimento := IncDay(Date, 30);

      FormaPgto := 'DINHEIRO';
      if Body.TryGetValue<string>('forma_pagamento', FormaPgto) then
        FormaPgto := UpperCase(Trim(FormaPgto));
      if FormaPgto.IsEmpty then
        FormaPgto := 'DINHEIRO';

      Conta := 0; Body.TryGetValue<Integer>('conta', Conta);
      PDV := 1; Body.TryGetValue<Integer>('pdv', PDV);
      if PDV <= 0 then PDV := 1;
      Funcionario := 1; Body.TryGetValue<Integer>('funcionario', Funcionario);
      SubDespesa := 0; Body.TryGetValue<Integer>('subdespesa', SubDespesa);
      SubDespNome := ''; Body.TryGetValue<string>('subdespesa_nome', SubDespNome);
      HistoricoDespesa := '';
      Body.TryGetValue<string>('historico_despesa', HistoricoDespesa);
      HistoricoDespesa := Trim(HistoricoDespesa);
      PermitirDuplicada := False; Body.TryGetValue<Boolean>('permitir_duplicada', PermitirDuplicada);

      if not Body.TryGetValue<TJSONArray>('itens', ItensArr) then
        ItensArr := nil;

      Transacao.StartTransaction;
      try
        Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conexao;
          Q.Transaction := Transacao;

          // Verifica duplicidade
          if (not PermitirDuplicada) and (not Chave.IsEmpty) then
          begin
            Q.SQL.Text := 'SELECT FIRST 1 NI_CODIGO FROM NFCE_IMPORTACOES WHERE NI_CHAVE = :CHAVE';
            Q.ParamByName('CHAVE').AsString := Chave;
            Q.Open;
            if not Q.IsEmpty then
            begin
              Transacao.Rollback;
              Res.Status(THTTPStatus.Conflict)
                .Send<TJSONObject>(ErrorResponse('Esta NFC-e ja foi importada anteriormente.', 'DUPLICATE_NFCE'));
              Exit;
            end;
          end;

          // Valida funcionario existente
          Funcionario := ObterFuncionarioValido(Conexao, Transacao, Funcionario);
          CodCaixa := ObterCaixa(Conexao, Transacao, PDV);
          CodForn := ObterOuCriarFornecedor(Conexao, Transacao, CnpjEmit, NomeEmit);

          // Pre-valida se precisa de SubDespesa e se ha itens de Compra
          TotalDespesaItens := 0;
          TotalCompraPrevisto := 0;
          TemItemCompra := False;
          if Assigned(ItensArr) then
          begin
            for I := 0 to ItensArr.Count - 1 do
            begin
              if ItensArr.Items[I] is TJSONObject then
              begin
                ItemObj := TJSONObject(ItensArr.Items[I]);
                DestinoItem := Modo;
                if Modo = 'COMPRA' then
                  ItemObj.TryGetValue<string>('destino', DestinoItem);
                DestinoItem := UpperCase(Trim(DestinoItem));
                if (DestinoItem <> 'COMPRA') and (DestinoItem <> 'DESPESA') and (DestinoItem <> 'IGNORAR') then
                  DestinoItem := Modo;
                VlrTotalItem := 0; ItemObj.TryGetValue<Double>('valor_total', VlrTotalItem);
                if DestinoItem = 'DESPESA' then
                  TotalDespesaItens := TotalDespesaItens + VlrTotalItem
                else if DestinoItem = 'COMPRA' then
                begin
                  TemItemCompra := True;
                  TotalCompraPrevisto := TotalCompraPrevisto + VlrTotalItem;
                end;
              end;
            end;
          end;

          if ((Modo = 'DESPESA') or (TotalDespesaItens > 0.001)) and (SubDespesa <= 0) then
          begin
            Transacao.Rollback;
            Res.Status(THTTPStatus.BadRequest)
              .Send<TJSONObject>(ErrorResponse('Selecione a Subdespesa para lancar os itens de despesa.', 'VALIDATION_ERROR'));
            Exit;
          end;

          if (SubDespesa > 0) and SubDespNome.IsEmpty then
          begin
            Q.Close;
            Q.SQL.Text := 'SELECT SUD_NOME FROM SUB_DES WHERE SUD_CODIGO = :SUD';
            Q.ParamByName('SUD').AsInteger := SubDespesa;
            Q.Open;
            if not Q.IsEmpty then
              SubDespNome := Q.FieldByName('SUD_NOME').AsString;
          end;

          CodImportacao := ProximoGen(Conexao, Transacao, 'GEN_NFCE_IMP');
          CodCompra := 0;
          CodCusto := 0;
          CodFat2 := 0;
          TemTabelaCompras := TProducaoService.TabelaExiste(Conexao, Transacao, 'COMPRAS');
          TemTabelaComEst := TProducaoService.TabelaExiste(Conexao, Transacao, 'COM_EST');

          if (Modo = 'COMPRA') and TemItemCompra then
          begin
            if TemTabelaCompras then
            begin
              if (TotalDespesaItens > 0.001) and (TotalCompraPrevisto > 0) then
                VlrCompraCab := TotalCompraPrevisto
              else
                VlrCompraCab := ValorTotalNota;

              CodCompra := ProximoGen(Conexao, Transacao, 'GEN_COM');
              Q.Close;
              Q.SQL.Text :=
                'INSERT INTO COMPRAS (' +
                '  COM_CODIGO, COM_VALOR, COM_HORA, COM_NATUREZA, COM_NF, COM_FOR, ' +
                '  COM_OUTROS, COM_IPI, COM_DATA, COM_FUN, COM_FRETE, COM_ICMS, COM_DARF, COM_DATAC, COM_DEVOLUCAO_P' +
                ') VALUES (' +
                '  :CODIGO, :VALOR, CURRENT_TIME, 1, :NF, :FORN, ' +
                '  0, 0, :DATA, :FUN, 0, 0, 0, :DATAC, ''N''' +
                ')';
              Q.ParamByName('CODIGO').AsInteger := CodCompra;
              Q.ParamByName('VALOR').AsFloat := RoundTo(VlrCompraCab, -4);
              Q.ParamByName('NF').AsInteger := StrToIntDef(SomenteDigitos(Numero), 0) mod 1000000;
              Q.ParamByName('FORN').AsInteger := CodForn;
              Q.ParamByName('DATA').AsDate := DataEmissao;
              Q.ParamByName('FUN').AsInteger := Funcionario;
              Q.ParamByName('DATAC').AsDate := EncodeDate(1900, 1, 1);
              Q.ExecSQL;
            end;
          end;

          // Processa itens
          TotalCompra := 0;
          TotalDespesaItens := 0;
          QtdItensEstoque := 0;
          QtdItensDespesa := 0;
          RecalculadasArr := TJSONArray.Create;
          try
            if Assigned(ItensArr) then
            begin
              for I := 0 to ItensArr.Count - 1 do
              begin
                if not (ItensArr.Items[I] is TJSONObject) then
                  Continue;
                ItemObj := TJSONObject(ItensArr.Items[I]);

                CodFornItem := ''; ItemObj.TryGetValue<string>('codigo_fornecedor', CodFornItem);
                EAN := ''; ItemObj.TryGetValue<string>('ean', EAN);
                DescricaoItem := ''; ItemObj.TryGetValue<string>('descricao', DescricaoItem);
                UnidNF := 'UN'; ItemObj.TryGetValue<string>('unidade_nf', UnidNF);
                QtdNF := 1; ItemObj.TryGetValue<Double>('quantidade_nf', QtdNF);
                if QtdNF <= 0 then QtdNF := 1;
                VlrUnitNF := 0; ItemObj.TryGetValue<Double>('valor_unitario_nf', VlrUnitNF);
                VlrTotalItem := 0; ItemObj.TryGetValue<Double>('valor_total', VlrTotalItem);
                FatorConv := 1; ItemObj.TryGetValue<Double>('fator_conversao', FatorConv);
                if FatorConv <= 0 then FatorConv := 1;

                DestinoItem := Modo;
                if Modo = 'COMPRA' then
                  ItemObj.TryGetValue<string>('destino', DestinoItem);
                DestinoItem := UpperCase(Trim(DestinoItem));
                if (DestinoItem <> 'COMPRA') and (DestinoItem <> 'DESPESA') and (DestinoItem <> 'IGNORAR') then
                  DestinoItem := Modo;

                ProCodigo := 0; ItemObj.TryGetValue<Integer>('pro_codigo', ProCodigo);
                CriarProduto := False; ItemObj.TryGetValue<Boolean>('criar_produto', CriarProduto);
                NovoNome := DescricaoItem; ItemObj.TryGetValue<string>('novo_produto_nome', NovoNome);
                if Trim(NovoNome).IsEmpty then NovoNome := DescricaoItem;
                NovoTipo := 'MP'; ItemObj.TryGetValue<string>('novo_produto_tipo', NovoTipo);
                NovoTipo := TProducaoService.NormalizarTipoProduto(NovoTipo);
                if (NovoTipo <> 'MP') and (NovoTipo <> 'REVENDA') then
                  NovoTipo := 'MP';
                NovoUnid := 'UN'; ItemObj.TryGetValue<string>('novo_produto_unidade', NovoUnid);
                NovoUnid := TProducaoService.NormalizarUnidade(NovoUnid);
                GrupoPro := 0; ItemObj.TryGetValue<Integer>('novo_produto_gru', GrupoPro);
                NovoValorV := 0; ItemObj.TryGetValue<Double>('novo_produto_valorv', NovoValorV);

                QtdEstoque := 0;
                CustoUnitEst := 0;

                if DestinoItem = 'COMPRA' then
                begin
                  if CriarProduto and (ProCodigo <= 0) then
                  begin
                    GrupoPro := ObterGrupoPadrao(Conexao, Transacao, GrupoPro);
                    if GrupoPro <= 0 then
                    begin
                      Transacao.Rollback;
                      Res.Status(THTTPStatus.BadRequest)
                        .Send<TJSONObject>(ErrorResponse('Nenhum grupo cadastrado em GRUPOS para criar o produto.', 'VALIDATION_ERROR'));
                      Exit;
                    end;

                    ProCodigo := ProximoCodigo(Conexao, Transacao, 'PRODUTOS', 'PRO_CODIGO');
                    UmCod := 0;
                    Q.Close;
                    Q.SQL.Text := 'SELECT FIRST 1 UM_CODIGO FROM UNIDADE_MED WHERE UPPER(TRIM(UM_UNIDADE)) = :U';
                    Q.ParamByName('U').AsString := Copy(NovoUnid, 1, 3);
                    Q.Open;
                    if not Q.IsEmpty then
                      UmCod := Q.FieldByName('UM_CODIGO').AsInteger;

                    Q.Close;
                    Q.SQL.Text :=
                      'INSERT INTO PRODUTOS (' +
                      '  PRO_CODIGO, PRO_FOR, PRO_QUANTIDADE, PRO_VALORV, PRO_VALORCM, PRO_VALORC, ' +
                      '  PRO_EMBALAGEM, PRO_DATAUC, PRO_GRU, PRO_DESCRICAO, PRO_DATAUA, PRO_CODBARRA, ' +
                      '  PRO_NOME, PRO_ESTADO, PRO_GTIN, PRO_UM, PRO_ESTOQUE, PRO_TIPO, PRO_IAT, PRO_IPPT' +
                      ') VALUES (' +
                      '  :CODIGO, :FORN, 0, :VALORV, 0, 0, ' +
                      '  :EMB, :DATAUC, :GRU, :DESCR, CURRENT_DATE, :BARRA, ' +
                      '  :NOME, ''ATIVO'', :GTIN, :UM, ''S'', :TIPO, ''A'', ''T''' +
                      ')';
                    Q.ParamByName('CODIGO').AsInteger := ProCodigo;
                    Q.ParamByName('FORN').AsInteger := CodForn;
                    Q.ParamByName('VALORV').AsFloat := NovoValorV;
                    Q.ParamByName('EMB').AsString := Copy(NovoUnid, 1, 10);
                    Q.ParamByName('DATAUC').AsDate := DataEmissao;
                    Q.ParamByName('GRU').AsInteger := GrupoPro;
                    Q.ParamByName('DESCR').AsString := Copy(Trim(NovoNome), 1, 30);
                    Q.ParamByName('BARRA').AsString := Copy(Trim(EAN), 1, 30);
                    Q.ParamByName('NOME').AsString := Copy(UpperCase(Trim(NovoNome)), 1, 50);
                    Q.ParamByName('GTIN').AsString := Copy(Trim(EAN), 1, 14);
                    Q.ParamByName('UM').AsInteger := UmCod;
                    Q.ParamByName('TIPO').AsString := NovoTipo;
                    Q.ExecSQL;
                  end;

                  if ProCodigo <= 0 then
                  begin
                    Transacao.Rollback;
                    Res.Status(THTTPStatus.BadRequest)
                      .Send<TJSONObject>(ErrorResponse('Item "' + DescricaoItem + '" marcado como Compra sem produto vinculado.', 'VALIDATION_ERROR'));
                    Exit;
                  end;

                  QtdEstoque := RoundTo(QtdNF * FatorConv, -4);
                  if QtdEstoque <= 0 then
                    QtdEstoque := 1;
                  CustoUnitEst := RoundTo(VlrTotalItem / QtdEstoque, -4);

                  OrigemHis := 'NFCE ' + IfThen(Numero.IsEmpty, IntToStr(CodImportacao), Numero) + ' - ' + NomeEmit;
                  DocHis := 'NF' + IfThen(Numero.IsEmpty, IntToStr(CodImportacao), Numero);
                  TProducaoService.AtualizarCustoEstoqueCompra(
                    Conexao, Transacao, ProCodigo, QtdEstoque, CustoUnitEst,
                    OrigemHis, DocHis, DataEmissao, NovoCM, NovoEst
                  );

                  if TemTabelaComEst and (CodCompra > 0) then
                  begin
                    CodCE := ProximoGen(Conexao, Transacao, 'GEN_CE');
                    Q.Close;
                    Q.SQL.Text :=
                      'INSERT INTO COM_EST (' +
                      '  CE_CODIGO, CE_VALOR, CE_QUANTIDADE, CE_IPI, CE_PRO, CE_COM, ' +
                      '  CE_VALORC, CE_VALORCM, CE_NVALORCM, CE_DATA_ULT_COMPRA' +
                      ') VALUES (' +
                      '  :CODIGO, :VALOR, :QTD, 0, :PRO, :COM, ' +
                      '  :VALORC, :VALORCM, :NVALORCM, :DATAUC' +
                      ')';
                    Q.ParamByName('CODIGO').AsInteger := CodCE;
                    Q.ParamByName('VALOR').AsFloat := RoundTo(VlrTotalItem, -4);
                    Q.ParamByName('QTD').AsFloat := RoundTo(QtdEstoque, -2);
                    Q.ParamByName('PRO').AsInteger := ProCodigo;
                    Q.ParamByName('COM').AsInteger := CodCompra;
                    Q.ParamByName('VALORC').AsFloat := RoundTo(CustoUnitEst, -4);
                    Q.ParamByName('VALORCM').AsFloat := RoundTo(NovoCM, -4);
                    Q.ParamByName('NVALORCM').AsFloat := RoundTo(NovoCM, -4);
                    Q.ParamByName('DATAUC').AsDate := DataEmissao;
                    Q.ExecSQL;
                  end;

                  TProducaoService.RecalcularEmCascata(Conexao, Transacao, ProCodigo, RecalculadasArr);
                  TotalCompra := TotalCompra + VlrTotalItem;
                  Inc(QtdItensEstoque);
                end
                else if DestinoItem = 'DESPESA' then
                begin
                  TotalDespesaItens := TotalDespesaItens + VlrTotalItem;
                  Inc(QtdItensDespesa);
                end;

                // Grava item da importacao
                Q.Close;
                Q.SQL.Text :=
                  'INSERT INTO NFCE_IMPORTACAO_ITENS (' +
                  '  NII_CODIGO, NII_NI, NII_COD_FORN, NII_EAN, NII_DESCRICAO, ' +
                  '  NII_QTD_NF, NII_UNIDADE_NF, NII_VLR_UNIT_NF, NII_VLR_TOTAL, ' +
                  '  NII_DESTINO, NII_PRO, NII_FATOR_CONV, NII_QTD_ESTOQUE, NII_CUSTO_UNIT_ESTOQUE' +
                  ') VALUES (' +
                  '  :CODIGO, :NI, :CODF, :EAN, :DESCR, ' +
                  '  :QTDNF, :UNIDNF, :VLRUNIT, :VLRTOT, ' +
                  '  :DESTINO, :PRO, :FATOR, :QTDEST, :CUSTOEST' +
                  ')';
                Q.ParamByName('CODIGO').AsInteger := ProximoGen(Conexao, Transacao, 'GEN_NFCE_IMP_IT');
                Q.ParamByName('NI').AsInteger := CodImportacao;
                Q.ParamByName('CODF').AsString := Copy(CodFornItem, 1, 60);
                Q.ParamByName('EAN').AsString := Copy(EAN, 1, 20);
                Q.ParamByName('DESCR').AsString := Copy(DescricaoItem, 1, 150);
                Q.ParamByName('QTDNF').AsFloat := QtdNF;
                Q.ParamByName('UNIDNF').AsString := Copy(UnidNF, 1, 10);
                Q.ParamByName('VLRUNIT').AsFloat := VlrUnitNF;
                Q.ParamByName('VLRTOT').AsFloat := VlrTotalItem;
                Q.ParamByName('DESTINO').AsString := DestinoItem;
                Q.ParamByName('PRO').AsInteger := ProCodigo;
                Q.ParamByName('FATOR').AsFloat := FatorConv;
                Q.ParamByName('QTDEST').AsFloat := QtdEstoque;
                Q.ParamByName('CUSTOEST').AsFloat := CustoUnitEst;
                Q.ExecSQL;

                // No modo "Nota inteira como Despesa", preserva vinculos de produtos existentes em PROD_FORN_MAP
                if (Modo = 'COMPRA') and (DestinoItem <> 'IGNORAR') then
                  UpsertMapaFornecedor(
                    Conexao, Transacao, CnpjEmit, CodFornItem, EAN, DescricaoItem,
                    DestinoItem, UnidNF, ProCodigo, SubDespesa, FatorConv
                  );
              end;
            end;

            // Financeiro da Compra
            if (Modo = 'COMPRA') and (TotalCompra > 0) then
            begin
              CodFat2 := ProximoGen(Conexao, Transacao, 'GEN_FAT2');
              CodPag := ProximoGen(Conexao, Transacao, 'GEN_PAG');

              Q.Close;
              Q.SQL.Text :=
                'INSERT INTO FATURAMENTO2 (' +
                '  FAT2_CODIGO, FAT2_TIPO, FAT2_VALOR, FAT2_DESCRICAO, FAT2_TIPOPGM, FAT2_PARCELAS, FAT2_JUROS, FAT2_DATA' +
                ') VALUES (' +
                '  :CODIGO, 1, :VALOR, :DESCRICAO, :TIPOPGM, 1, 0, :DATA' +
                ')';
              Q.ParamByName('CODIGO').AsInteger := CodFat2;
              Q.ParamByName('VALOR').AsCurrency := TotalCompra;
              Q.ParamByName('DESCRICAO').AsInteger := IfThen(CodCompra > 0, CodCompra, CodImportacao);
              Q.ParamByName('TIPOPGM').AsInteger := IfThen(CondicaoPgto = 'V', 1, 2);
              Q.ParamByName('DATA').AsDate := DataEmissao;
              Q.ExecSQL;

              if CodCompra > 0 then
              begin
                Q.Close;
                Q.SQL.Text := 'UPDATE COMPRAS SET COM_FAT2 = :FAT2 WHERE COM_CODIGO = :COM';
                Q.ParamByName('FAT2').AsInteger := CodFat2;
                Q.ParamByName('COM').AsInteger := CodCompra;
                Q.ExecSQL;
              end;

              Q.Close;
              Q.SQL.Text :=
                'INSERT INTO PAGAMENTOS (' +
                '  PAG_CODIGO, PAG_VALOR, PAG_VENCIMENTO, PAG_JUROS, PAG_ESTADO, PAG_DUPLICATA, PAG_FPG, ' +
                '  PAG_FAT2, PAG_DESCONTOS, PAG_CAI, PAG_TIPO, PAG_SITUACAO, PAG_OBS, PAG_CON, PAG_DATAC' +
                ') VALUES (' +
                '  :CODIGO, :VALOR, :VENC, 0, :ESTADO, :DUPL, 1, ' +
                '  :FAT2, 0, :CAIXA, :TIPO, 0, :OBS, -1, :DATAC' +
                ')';
              Q.ParamByName('CODIGO').AsInteger := CodPag;
              Q.ParamByName('VALOR').AsCurrency := TotalCompra;
              Q.ParamByName('VENC').AsDate := IfThen(CondicaoPgto = 'V', DataEmissao, DataVencimento);
              Q.ParamByName('ESTADO').AsInteger := IfThen(CondicaoPgto = 'V', 3, 1);
              Q.ParamByName('DUPL').AsString := CodFat2.ToString + '-1/1';
              Q.ParamByName('FAT2').AsInteger := CodFat2;
              Q.ParamByName('CAIXA').AsInteger := CodCaixa;
              Q.ParamByName('TIPO').AsString := Copy(FormaPgto, 1, 20);
              Q.ParamByName('OBS').AsString := Copy('NFCE ' + Numero + ' - ' + NomeEmit, 1, 100);
              Q.ParamByName('DATAC').AsDate := EncodeDate(1900, 1, 1);
              Q.ExecSQL;

              if CondicaoPgto = 'V' then
              begin
                CodMov := ProximoGen(Conexao, Transacao, 'GEN_MOV');
                CodPP := ProximoGen(Conexao, Transacao, 'GEN_PP');
                InserirMovimentacao(
                  Conexao, Transacao, CodMov, 0, TotalCompra,
                  'CMP - ' + NomeEmit, '2.1', 'COMPRA', 0, CodCaixa
                );

                Q.Close;
                Q.SQL.Text :=
                  'INSERT INTO PAG_PGM (' +
                  '  PP_CODIGO, PP_DATAPGM, PP_DINHEIRO, PP_CHEQUE, PP_MOV, PP_PAG, PP_HORA, PP_FUN, PP_CAI, PP_JUROS, PP_DESCONTOS' +
                  ') VALUES (' +
                  '  :CODIGO, :DATA, :VALOR, 0, :MOV, :PAG, CURRENT_TIME, :FUN, :CAIXA, 0, 0' +
                  ')';
                Q.ParamByName('CODIGO').AsInteger := CodPP;
                Q.ParamByName('DATA').AsDate := Date;
                Q.ParamByName('VALOR').AsCurrency := TotalCompra;
                Q.ParamByName('MOV').AsInteger := CodMov;
                Q.ParamByName('PAG').AsInteger := CodPag;
                Q.ParamByName('FUN').AsInteger := Funcionario;
                Q.ParamByName('CAIXA').AsInteger := CodCaixa;
                Q.ExecSQL;

                if Conta > 0 then
                begin
                  InserirMovimentacao(
                    Conexao, Transacao, ProximoGen(Conexao, Transacao, 'GEN_MOV'),
                    TotalCompra, 0, 'TR - ' + NomeEmit, '5.4', 'TRANSFERENCIA', 0, CodCaixa, 'B'
                  );
                  InserirMovimentacao(
                    Conexao, Transacao, ProximoGen(Conexao, Transacao, 'GEN_MOV'),
                    0, TotalCompra, 'CMP - ' + NomeEmit, '2.1', 'COMPRA', Conta, CodCaixa, 'B'
                  );
                end;
              end;
            end;

            // Financeiro da Despesa (nota inteira como DESPESA ou itens marcados como DESPESA)
            if Modo = 'DESPESA' then
            begin
              TotalLancamentoDespesa := ValorTotalNota;
              if TotalLancamentoDespesa <= 0 then
                TotalLancamentoDespesa := TotalDespesaItens;
            end
            else
              TotalLancamentoDespesa := TotalDespesaItens;

            if TotalLancamentoDespesa > 0 then
            begin
              if Modo = 'DESPESA' then
                QtdItensDespesa := IfThen(Assigned(ItensArr), ItensArr.Count, 1);

              CodFat2 := ProximoGen(Conexao, Transacao, 'GEN_FAT2');
              CodCusto := ProximoGen(Conexao, Transacao, 'GEN_CUST');
              CodPag := ProximoGen(Conexao, Transacao, 'GEN_PAG');
              if not HistoricoDespesa.IsEmpty then
              begin
                HistoricoCusto := Copy(HistoricoDespesa, 1, 20);
                ObsDespesa := Copy(HistoricoDespesa, 1, 100);
              end
              else
              begin
                HistoricoCusto := Copy('NFCE ' + Numero + ' ' + NomeEmit, 1, 20);
                ObsDespesa := Copy('NFCE ' + Numero + ' - ' + NomeEmit, 1, 100);
              end;

              Q.Close;
              Q.SQL.Text :=
                'INSERT INTO CUSTOS (' +
                '  CUST_CODIGO, CUST_DATA, CUST_NDOC, CUST_HISTORICO, CUST_SUD, CUST_VALOR, ' +
                '  CUST_FUN, CUST_DATAC, CUST_FAT2, CUST_TIPO, CUST_COD_FUN, CUST_COD_FOR' +
                ') VALUES (' +
                '  :CODIGO, :DATA, :NDOC, :HISTORICO, :SUD, :VALOR, ' +
                '  :FUN, :DATAC, :FAT2, ''D'', 0, :COD_FOR' +
                ')';
              Q.ParamByName('CODIGO').AsInteger := CodCusto;
              Q.ParamByName('DATA').AsDate := DataEmissao;
              Q.ParamByName('NDOC').AsString := Copy(IfThen(Numero.IsEmpty, CodImportacao.ToString, Numero), 1, 10);
              Q.ParamByName('HISTORICO').AsString := HistoricoCusto;
              Q.ParamByName('SUD').AsInteger := SubDespesa;
              Q.ParamByName('VALOR').AsCurrency := TotalLancamentoDespesa;
              Q.ParamByName('FUN').AsInteger := Funcionario;
              Q.ParamByName('DATAC').AsDate := EncodeDate(1900, 1, 1);
              Q.ParamByName('FAT2').AsInteger := CodFat2;
              Q.ParamByName('COD_FOR').AsInteger := CodForn;
              Q.ExecSQL;

              Q.Close;
              Q.SQL.Text :=
                'INSERT INTO FATURAMENTO2 (' +
                '  FAT2_CODIGO, FAT2_TIPO, FAT2_VALOR, FAT2_DESCRICAO, FAT2_TIPOPGM, FAT2_PARCELAS, FAT2_JUROS, FAT2_DATA' +
                ') VALUES (' +
                '  :CODIGO, 2, :VALOR, :DESCRICAO, :TIPOPGM, 1, 0, :DATA' +
                ')';
              Q.ParamByName('CODIGO').AsInteger := CodFat2;
              Q.ParamByName('VALOR').AsCurrency := TotalLancamentoDespesa;
              Q.ParamByName('DESCRICAO').AsInteger := CodCusto;
              Q.ParamByName('TIPOPGM').AsInteger := IfThen(CondicaoPgto = 'V', 1, 2);
              Q.ParamByName('DATA').AsDate := DataEmissao;
              Q.ExecSQL;

              Q.Close;
              Q.SQL.Text :=
                'INSERT INTO PAGAMENTOS (' +
                '  PAG_CODIGO, PAG_VALOR, PAG_VENCIMENTO, PAG_JUROS, PAG_ESTADO, PAG_DUPLICATA, PAG_FPG, ' +
                '  PAG_FAT2, PAG_DESCONTOS, PAG_CAI, PAG_TIPO, PAG_SITUACAO, PAG_OBS, PAG_CON, PAG_DATAC' +
                ') VALUES (' +
                '  :CODIGO, :VALOR, :VENC, 0, :ESTADO, :DUPL, 1, ' +
                '  :FAT2, 0, :CAIXA, :TIPO, 0, :OBS, -1, :DATAC' +
                ')';
              Q.ParamByName('CODIGO').AsInteger := CodPag;
              Q.ParamByName('VALOR').AsCurrency := TotalLancamentoDespesa;
              Q.ParamByName('VENC').AsDate := IfThen(CondicaoPgto = 'V', DataEmissao, DataVencimento);
              Q.ParamByName('ESTADO').AsInteger := IfThen(CondicaoPgto = 'V', 3, 1);
              Q.ParamByName('DUPL').AsString := CodFat2.ToString + '-1/1';
              Q.ParamByName('FAT2').AsInteger := CodFat2;
              Q.ParamByName('CAIXA').AsInteger := CodCaixa;
              Q.ParamByName('TIPO').AsString := Copy(FormaPgto, 1, 20);
              Q.ParamByName('OBS').AsString := ObsDespesa;
              Q.ParamByName('DATAC').AsDate := EncodeDate(1900, 1, 1);
              Q.ExecSQL;

              if CondicaoPgto = 'V' then
              begin
                CodMov := ProximoGen(Conexao, Transacao, 'GEN_MOV');
                CodPP := ProximoGen(Conexao, Transacao, 'GEN_PP');
                InserirMovimentacao(
                  Conexao, Transacao, CodMov, 0, TotalLancamentoDespesa,
                  'DES - ' + SubDespNome, '2.2', 'DESPESA', 0, CodCaixa
                );

                Q.Close;
                Q.SQL.Text :=
                  'INSERT INTO PAG_PGM (' +
                  '  PP_CODIGO, PP_DATAPGM, PP_DINHEIRO, PP_CHEQUE, PP_MOV, PP_PAG, PP_HORA, PP_FUN, PP_CAI, PP_JUROS, PP_DESCONTOS' +
                  ') VALUES (' +
                  '  :CODIGO, :DATA, :VALOR, 0, :MOV, :PAG, CURRENT_TIME, :FUN, :CAIXA, 0, 0' +
                  ')';
                Q.ParamByName('CODIGO').AsInteger := CodPP;
                Q.ParamByName('DATA').AsDate := Date;
                Q.ParamByName('VALOR').AsCurrency := TotalLancamentoDespesa;
                Q.ParamByName('MOV').AsInteger := CodMov;
                Q.ParamByName('PAG').AsInteger := CodPag;
                Q.ParamByName('FUN').AsInteger := Funcionario;
                Q.ParamByName('CAIXA').AsInteger := CodCaixa;
                Q.ExecSQL;

                if Conta > 0 then
                begin
                  InserirMovimentacao(
                    Conexao, Transacao, ProximoGen(Conexao, Transacao, 'GEN_MOV'),
                    TotalLancamentoDespesa, 0, 'TR - ' + SubDespNome, '5.4', 'TRANSFERENCIA', 0, CodCaixa, 'B'
                  );
                  InserirMovimentacao(
                    Conexao, Transacao, ProximoGen(Conexao, Transacao, 'GEN_MOV'),
                    0, TotalLancamentoDespesa, 'DES - ' + SubDespNome, '2.2', 'DESPESA', Conta, CodCaixa, 'B'
                  );
                end;
              end;
            end;

            // Grava cabecalho NFCE_IMPORTACOES
            Q.Close;
            Q.SQL.Text :=
              'INSERT INTO NFCE_IMPORTACOES (' +
              '  NI_CODIGO, NI_CHAVE, NI_URL, NI_NUMERO, NI_SERIE, NI_DATA_EMISSAO, NI_DATA_IMPORT, ' +
              '  NI_CNPJ_EMIT, NI_NOME_EMIT, NI_FOR, NI_MODO, NI_VALOR_TOTAL, NI_VALOR_DESCONTO, ' +
              '  NI_COM_CODIGO, NI_CUST_CODIGO, NI_FAT2_CODIGO, NI_CONTA, NI_FORMA_PGTO, NI_FUN' +
              ') VALUES (' +
              '  :CODIGO, :CHAVE, :URL, :NUMERO, :SERIE, :DATA_EMI, CURRENT_TIMESTAMP, ' +
              '  :CNPJ, :NOME, :FORN, :MODO, :VLRTOT, :VLRDESC, ' +
              '  :COM, :CUST, :FAT2, :CONTA, :PGTO, :FUN' +
              ')';
            Q.ParamByName('CODIGO').AsInteger := CodImportacao;
            Q.ParamByName('CHAVE').AsString := Copy(Chave, 1, 44);
            Q.ParamByName('URL').AsString := Copy(Url, 1, 500);
            Q.ParamByName('NUMERO').AsString := Copy(Numero, 1, 20);
            Q.ParamByName('SERIE').AsString := Copy(Serie, 1, 10);
            Q.ParamByName('DATA_EMI').AsDate := DataEmissao;
            Q.ParamByName('CNPJ').AsString := Copy(CnpjEmit, 1, 20);
            Q.ParamByName('NOME').AsString := Copy(NomeEmit, 1, 120);
            Q.ParamByName('FORN').AsInteger := CodForn;
            Q.ParamByName('MODO').AsString := Modo;
            Q.ParamByName('VLRTOT').AsCurrency := ValorTotalNota;
            Q.ParamByName('VLRDESC').AsCurrency := ValorDescNota;
            Q.ParamByName('COM').AsInteger := CodCompra;
            Q.ParamByName('CUST').AsInteger := CodCusto;
            Q.ParamByName('FAT2').AsInteger := CodFat2;
            Q.ParamByName('CONTA').AsInteger := Conta;
            Q.ParamByName('PGTO').AsString := Copy(FormaPgto, 1, 20);
            Q.ParamByName('FUN').AsInteger := Funcionario;
            Q.ExecSQL;

            Transacao.Commit;

            RespObj := TJSONObject.Create;
            RespObj.AddPair('importacao_codigo', TJSONNumber.Create(CodImportacao));
            RespObj.AddPair('fornecedor_codigo', TJSONNumber.Create(CodForn));
            RespObj.AddPair('compra_codigo', TJSONNumber.Create(CodCompra));
            RespObj.AddPair('custo_codigo', TJSONNumber.Create(CodCusto));
            RespObj.AddPair('itens_estoque', TJSONNumber.Create(QtdItensEstoque));
            RespObj.AddPair('itens_despesa', TJSONNumber.Create(QtdItensDespesa));
            RespObj.AddPair('valor_compra', TJSONNumber.Create(RoundTo(TotalCompra, -2)));
            RespObj.AddPair('valor_despesa', TJSONNumber.Create(RoundTo(TotalLancamentoDespesa, -2)));
            RespObj.AddPair('valor_total', TJSONNumber.Create(RoundTo(ValorTotalNota, -2)));
            RespObj.AddPair('fichas_recalculadas', RecalculadasArr);
            RecalculadasArr := nil;

            Res.Status(THTTPStatus.Created)
              .Send<TJSONObject>(SuccessResponse(RespObj, 'NFC-e importada e lancada com sucesso.'));
          finally
            if Assigned(RecalculadasArr) then
              RecalculadasArr.Free;
          end;
        finally
          Q.DisposeOf;
        end;
      except
        if Transacao.Active then
          Transacao.Rollback;
        raise;
      end;
    except
      on E: Exception do
        Res.Status(THTTPStatus.InternalServerError)
          .Send<TJSONObject>(ErrorResponse('Falha ao confirmar importacao da NFC-e.', 'INTERNAL_ERROR', E.Message));
    end;
  finally
    Transacao.DisposeOf;
    BancoDados.Disconnected(IndiceConexao);
    Body.Free;
  end;
end;

class procedure TNFCeController.Historico(Req: THorseRequest; Res: THorseResponse);
var
  Query: iQuery;
  Lista: TJSONArray;
  Item: TJSONObject;
begin
  TProducaoService.GarantirEstrutura;
  Query := TDatabase.Query;
  Lista := TJSONArray.Create;
  try
    Query.Clear;
    Query.Add('SELECT FIRST 50');
    Query.Add('  N.NI_CODIGO, N.NI_CHAVE, N.NI_NUMERO, N.NI_SERIE, N.NI_DATA_EMISSAO,');
    Query.Add('  N.NI_DATA_IMPORT, N.NI_CNPJ_EMIT, N.NI_NOME_EMIT, N.NI_MODO,');
    Query.Add('  N.NI_VALOR_TOTAL, N.NI_VALOR_DESCONTO, N.NI_COM_CODIGO, N.NI_CUST_CODIGO,');
    Query.Add('  N.NI_FORMA_PGTO,');
    Query.Add('  (SELECT COUNT(*) FROM NFCE_IMPORTACAO_ITENS I WHERE I.NII_NI = N.NI_CODIGO) AS QTD_ITENS');
    Query.Add('FROM NFCE_IMPORTACOES N');
    Query.Add('ORDER BY N.NI_CODIGO DESC');
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('NI_CODIGO').AsInteger));
      Item.AddPair('chave', Query.DataSet.FieldByName('NI_CHAVE').AsString);
      Item.AddPair('numero', Query.DataSet.FieldByName('NI_NUMERO').AsString);
      Item.AddPair('serie', Query.DataSet.FieldByName('NI_SERIE').AsString);
      if not Query.DataSet.FieldByName('NI_DATA_EMISSAO').IsNull then
        Item.AddPair('data_emissao', FormatDateTime('yyyy-mm-dd', Query.DataSet.FieldByName('NI_DATA_EMISSAO').AsDateTime))
      else
        Item.AddPair('data_emissao', '');
      if not Query.DataSet.FieldByName('NI_DATA_IMPORT').IsNull then
        Item.AddPair('data_importacao', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Query.DataSet.FieldByName('NI_DATA_IMPORT').AsDateTime))
      else
        Item.AddPair('data_importacao', '');
      Item.AddPair('cnpj_emitente', Query.DataSet.FieldByName('NI_CNPJ_EMIT').AsString);
      Item.AddPair('nome_emitente', Query.DataSet.FieldByName('NI_NOME_EMIT').AsString);
      Item.AddPair('modo', Query.DataSet.FieldByName('NI_MODO').AsString);
      Item.AddPair('valor_total', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('NI_VALOR_TOTAL').AsFloat, -2)));
      Item.AddPair('valor_desconto', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('NI_VALOR_DESCONTO').AsFloat, -2)));
      Item.AddPair('compra_codigo', TJSONNumber.Create(Query.DataSet.FieldByName('NI_COM_CODIGO').AsInteger));
      Item.AddPair('custo_codigo', TJSONNumber.Create(Query.DataSet.FieldByName('NI_CUST_CODIGO').AsInteger));
      Item.AddPair('forma_pagamento', Query.DataSet.FieldByName('NI_FORMA_PGTO').AsString);
      Item.AddPair('qtd_itens', TJSONNumber.Create(Query.DataSet.FieldByName('QTD_ITENS').AsInteger));
      Lista.AddElement(Item);
      Query.DataSet.Next;
    end;

    Res.Send<TJSONObject>(SuccessResponse(Lista, 'Historico de NFC-e carregado.'));
    Lista := nil;
  finally
    if Assigned(Lista) then
      Lista.Free;
  end;
end;

class procedure TNFCeController.Registrar;
begin
  THorse.Post('/v1/nfce/parse', Parse);
  THorse.Post('/v1/nfce/confirmar', Confirmar);
  THorse.Get('/v1/nfce/historico', Historico);
end;

end.
