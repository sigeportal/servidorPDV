unit Relatorios.Controller;

interface

uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  UnitConnection.Model.Interfaces, UnitTamanhos.Model, UnitVeAdicionais.Model,
  UnitAdicionais.Model;

type
  TRelatoriosController = class
  private
    class function SuccessResponse(AData: TJSONValue; const AMessage: string = ''): TJSONObject; static;
    class function ErrorResponse(const AMessage, ACode: string; const ADetails: string = ''): TJSONObject; static;
    class function ParseDateParam(const AValue: string; out ADate: TDate): Boolean; static;
  public
    class procedure Registrar;
    class procedure Resumo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure VendasAnalitico(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  end;

implementation

uses
  UnitDatabase;

class function TRelatoriosController.SuccessResponse(AData: TJSONValue; const AMessage: string): TJSONObject;
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

class function TRelatoriosController.ErrorResponse(const AMessage, ACode, ADetails: string): TJSONObject;
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

class function TRelatoriosController.ParseDateParam(const AValue: string; out ADate: TDate): Boolean;
var
  DateTimeValue: TDateTime;
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create;
  FS.DateSeparator := '-';
  FS.ShortDateFormat := 'yyyy-mm-dd';

  if TryStrToDate(AValue, DateTimeValue, FS) then
  begin
    ADate := DateOf(DateTimeValue);
    Exit(True);
  end;

  FS.DateSeparator := '/';
  FS.ShortDateFormat := 'dd/mm/yyyy';

  Result := TryStrToDate(AValue, DateTimeValue, FS);
  if Result then
    ADate := DateOf(DateTimeValue);
end;

class procedure TRelatoriosController.VendasAnalitico(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query, Aux, QueryCaixa: iQuery;
  DataInicio, DataFim: TDate;
  Cliente, Grupo, PDV, CaixaAtual: Integer;
  TodosCaixas: Boolean;
  TipoPedido, SQLCliente, SQLGrupo, SQLTipo, SQLCaixa, SQLCaixaCanc: string;
  DataObj, PeriodoObj, TotaisObj, VendaObj, ItemObj, AdicionalObj, PagamentoObj, ResumoObj: TJSONObject;
  VendasArr, ItensArr, AdicionaisArr, PagamentosArr, ResumoArr: TJSONArray;
  VendaAtual, VendaCodigo: Integer;
  SubTotal, TotalAdicionais, TotalTaxaEntrega, TotalCanceladas, TotalVista, TotalPrazo, TotalGeral, TotalLucro: Currency;
  Tamanhos: TTamanhos;
  VeAdicionais: TVeAdicionais;
  Adicionais: TAdicionais;
begin
  DataInicio := Date - 7;
  DataFim := Date;
  Cliente := 0;
  Grupo := 0;
  PDV := 0;
  CaixaAtual := 0;
  TodosCaixas := False;
  TipoPedido := '';
  Tamanhos := TTamanhos.Create(TDatabase.Connection);
  VeAdicionais := TVeAdicionais.Create(TDatabase.Connection);
  Adicionais := TAdicionais.Create(TDatabase.Connection);
  try
    Tamanhos.CriaTabela;
    VeAdicionais.CriaTabela;
    Adicionais.CriaTabela;
  finally
    Tamanhos.DisposeOf;
    VeAdicionais.DisposeOf;
    Adicionais.DisposeOf;
  end;
  ////
  if Req.Query.ContainsKey('dataInicio') and
     (not ParseDateParam(Req.Query.Items['dataInicio'], DataInicio)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro dataInicio invalido. Use yyyy-mm-dd.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if Req.Query.ContainsKey('dataFim') and
     (not ParseDateParam(Req.Query.Items['dataFim'], DataFim)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro dataFim invalido. Use yyyy-mm-dd.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if DataFim < DataInicio then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('dataFim nao pode ser menor que dataInicio.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if Req.Query.ContainsKey('cliente') and
     (not TryStrToInt(Req.Query.Items['cliente'], Cliente)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro cliente invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if Req.Query.ContainsKey('grupo') and
     (not TryStrToInt(Req.Query.Items['grupo'], Grupo)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro grupo invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if Req.Query.ContainsKey('tipoPedido') then
    TipoPedido := UpperCase(Trim(Req.Query.Items['tipoPedido']));

  if Req.Query.ContainsKey('pdv') and
     (not TryStrToInt(Req.Query.Items['pdv'], PDV)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro pdv invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if Req.Query.ContainsKey('todosCaixas') then
    TodosCaixas := SameText(Req.Query.Items['todosCaixas'], 'true') or (Req.Query.Items['todosCaixas'] = '1');

  if Req.Query.ContainsKey('caixa') and
     (not TryStrToInt(Req.Query.Items['caixa'], CaixaAtual)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro caixa invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if (not TodosCaixas) and (CaixaAtual = 0) and (PDV > 0) then
  begin
    QueryCaixa := TDatabase.Query;
    try
      QueryCaixa.Clear;
      QueryCaixa.Add('SELECT FIRST 1 CAI_CODIGO, CAI_DATAI FROM CAIXA WHERE CAI_PDV = :PDV AND CAI_HORAF IS NULL ORDER BY CAI_CODIGO DESC');
      QueryCaixa.AddParam('PDV', PDV);
      QueryCaixa.Open;
      if not QueryCaixa.DataSet.IsEmpty then
      begin
        CaixaAtual := QueryCaixa.DataSet.FieldByName('CAI_CODIGO').AsInteger;
        if (not QueryCaixa.DataSet.FieldByName('CAI_DATAI').IsNull) and
           (DataInicio > QueryCaixa.DataSet.FieldByName('CAI_DATAI').AsDateTime) then
          DataInicio := QueryCaixa.DataSet.FieldByName('CAI_DATAI').AsDateTime;
      end
      else
      begin
        QueryCaixa.Clear;
        QueryCaixa.Add('SELECT FIRST 1 CAI_CODIGO, CAI_DATAI FROM CAIXA WHERE CAI_PDV = :PDV ORDER BY CAI_CODIGO DESC');
        QueryCaixa.AddParam('PDV', PDV);
        QueryCaixa.Open;
        if not QueryCaixa.DataSet.IsEmpty then
        begin
          CaixaAtual := QueryCaixa.DataSet.FieldByName('CAI_CODIGO').AsInteger;
          if (not QueryCaixa.DataSet.FieldByName('CAI_DATAI').IsNull) and
             (DataInicio > QueryCaixa.DataSet.FieldByName('CAI_DATAI').AsDateTime) then
            DataInicio := QueryCaixa.DataSet.FieldByName('CAI_DATAI').AsDateTime;
        end;
      end;
    finally
      QueryCaixa := nil;
    end;
  end;

  SQLCliente := '';
  SQLGrupo := '';
  SQLTipo := '';
  SQLCaixa := '';
  SQLCaixaCanc := '';
  if Cliente > 0 then
    SQLCliente := ' AND CLI_CODIGO = :CLIENTE';
  if Grupo > 0 then
    SQLGrupo := ' AND GRU_G1 = :GRUPO';
  if not TipoPedido.IsEmpty then
    SQLTipo := ' AND VEN_TIPO_PEDIDO = :TIPO_PEDIDO';
  if (not TodosCaixas) and (CaixaAtual > 0) then
  begin
    SQLCaixa := ' AND VEN_FAT IN (SELECT REC_FAT FROM RECEBIMENTOS WHERE REC_CAI = :CAIXA_ATUAL)';
    SQLCaixaCanc := ' AND VEN_FAT IN (SELECT REC_FAT FROM RECEBIMENTOS WHERE REC_CAI = :CAIXA_ATUAL)';
  end
  else if (not TodosCaixas) and (PDV > 0) and (CaixaAtual = 0) then
  begin
    SQLCaixa := ' AND 1 = 0';
    SQLCaixaCanc := ' AND 1 = 0';
  end;

  Query := TDatabase.Query;
  Aux := TDatabase.Query;
  DataObj := TJSONObject.Create;
  PeriodoObj := TJSONObject.Create;
  TotaisObj := TJSONObject.Create;
  VendasArr := TJSONArray.Create;
  ResumoArr := TJSONArray.Create;
  VendaObj := nil;
  ItensArr := nil;
  PagamentosArr := nil;
  VendaAtual := -1;
  SubTotal := 0;
  TotalAdicionais := 0;
  TotalTaxaEntrega := 0;
  TotalCanceladas := 0;
  TotalVista := 0;
  TotalPrazo := 0;
  TotalGeral := 0;
  TotalLucro := 0;

  try
    Query.Clear;
    Query.Add('SELECT VEN_CODIGO, VEN_FAT, FUN_CODIGO, VEN_DATA, VEN_HORA,');
    Query.Add('       VEN_DIFERENCA, VE_CODIGO, VE_QUANTIDADE, VE_VALOR, VEN_VALOR, VE_LUCRO,');
    Query.Add('       CASE WHEN ((VEN_NOME_CLIENTE <> '''') AND (VEN_CLI = 1)) THEN VEN_NOME_CLIENTE ELSE CLI_NOME END NOME_CLIENTE,');
    Query.Add('       PRO_NOME, VEN_DATAC, PRO_CODIGO, PRO_ABC, VE_VALORB, VE_DESCONTO, TAM_SIGLA,');
    Query.Add('       VEN_TAXA_ENTREGA, COALESCE(TP_CONDICAO, ''V'') CONDICAO_PGTO');
    Query.Add('FROM VENDAS');
    Query.Add('JOIN VEN_EST ON VEN_CODIGO = VE_VEN AND VEN_DATAC = ''01/01/1900''');
    Query.Add('JOIN FUNCIONARIOS ON VEN_FUN = FUN_CODIGO');
    Query.Add('JOIN CLIENTES ON VEN_CLI = CLI_CODIGO');
    Query.Add('JOIN PRODUTOS ON VE_PRO = PRO_CODIGO');
    if Grupo > 0 then
      Query.Add('JOIN GRUPOS ON PRO_GRU = GRU_CODIGO');
    Query.Add('LEFT JOIN FORMAS_PAGAMENTO ON FP_CODIGO = VEN_FORMA_PGTO');
    Query.Add('LEFT JOIN TIPO_PGM ON FP_TIPO_PGM = TP_CODIGO');
    Query.Add('LEFT JOIN GRADES ON VE_GRA = GRA_CODIGO');
    Query.Add('LEFT JOIN TAMANHOS ON GRA_TAM = TAM_CODIGO');
    Query.Add('WHERE VEN_DATA BETWEEN :DATA_INI AND :DATA_FIM' + SQLCliente + SQLGrupo + SQLTipo + SQLCaixa);
    Query.Add('ORDER BY VEN_CODIGO, VE_CODIGO');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    if Cliente > 0 then
      Query.AddParam('CLIENTE', Cliente);
    if Grupo > 0 then
      Query.AddParam('GRUPO', Grupo);
    if not TipoPedido.IsEmpty then
      Query.AddParam('TIPO_PEDIDO', TipoPedido);
    if (not TodosCaixas) and (CaixaAtual > 0) then
      Query.AddParam('CAIXA_ATUAL', CaixaAtual);
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      VendaCodigo := Query.DataSet.FieldByName('VEN_CODIGO').AsInteger;
      if VendaAtual <> VendaCodigo then
      begin
        VendaAtual := VendaCodigo;
        VendaObj := TJSONObject.Create;
        ItensArr := TJSONArray.Create;
        PagamentosArr := TJSONArray.Create;

        VendaObj.AddPair('codigo', TJSONNumber.Create(VendaCodigo));
        VendaObj.AddPair('faturamento', TJSONNumber.Create(Query.DataSet.FieldByName('VEN_FAT').AsInteger));
        VendaObj.AddPair('funcionario', TJSONNumber.Create(Query.DataSet.FieldByName('FUN_CODIGO').AsInteger));
        VendaObj.AddPair('data', FormatDateTime('yyyy-mm-dd', Query.DataSet.FieldByName('VEN_DATA').AsDateTime));
        VendaObj.AddPair('hora', FormatDateTime('hh:nn:ss', Query.DataSet.FieldByName('VEN_HORA').AsDateTime));
        VendaObj.AddPair('cliente', Query.DataSet.FieldByName('NOME_CLIENTE').AsString);
        VendaObj.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('VEN_VALOR').AsCurrency));
        VendaObj.AddPair('taxa_entrega', TJSONNumber.Create(Query.DataSet.FieldByName('VEN_TAXA_ENTREGA').AsCurrency));
        VendaObj.AddPair('condicao_pgto', Query.DataSet.FieldByName('CONDICAO_PGTO').AsString);

        Aux.Clear;
        Aux.Add('SELECT FAT_DATA, REC_DUPLICATA, REC_VENCIMENTO, REC_TIPO, REC_VALOR+REC_JUROS-REC_DESCONTOS VALOR');
        Aux.Add('FROM VENDAS JOIN FATURAMENTOS ON VEN_FAT = FAT_CODIGO');
        Aux.Add('JOIN RECEBIMENTOS ON FAT_CODIGO = REC_FAT');
        Aux.Add('WHERE VEN_CODIGO = :VENDA AND (REC_SITUACAO >= 0 AND REC_SITUACAO < 2)');
        Aux.Add('ORDER BY REC_VENCIMENTO');
        Aux.AddParam('VENDA', VendaCodigo);
        Aux.Open;
        Aux.DataSet.First;
        while not Aux.DataSet.Eof do
        begin
          PagamentoObj := TJSONObject.Create;
          PagamentoObj.AddPair('duplicata', Aux.DataSet.FieldByName('REC_DUPLICATA').AsString);
          PagamentoObj.AddPair('vencimento', FormatDateTime('yyyy-mm-dd', Aux.DataSet.FieldByName('REC_VENCIMENTO').AsDateTime));
          PagamentoObj.AddPair('tipo', Aux.DataSet.FieldByName('REC_TIPO').AsString);
          PagamentoObj.AddPair('valor', TJSONNumber.Create(Aux.DataSet.FieldByName('VALOR').AsCurrency));
          PagamentosArr.AddElement(PagamentoObj);
          Aux.DataSet.Next;
        end;

        VendaObj.AddPair('pagamentos', PagamentosArr);
        VendaObj.AddPair('itens', ItensArr);
        VendasArr.AddElement(VendaObj);
      end;

      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('VE_CODIGO').AsInteger));
      ItemObj.AddPair('produto', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
      ItemObj.AddPair('descricao', Query.DataSet.FieldByName('PRO_NOME').AsString);
      ItemObj.AddPair('abc', Query.DataSet.FieldByName('PRO_ABC').AsString);
      ItemObj.AddPair('tamanho', Query.DataSet.FieldByName('TAM_SIGLA').AsString);
      ItemObj.AddPair('quantidade', TJSONNumber.Create(Query.DataSet.FieldByName('VE_QUANTIDADE').AsFloat));
      ItemObj.AddPair('valor_unitario', TJSONNumber.Create(Query.DataSet.FieldByName('VE_VALOR').AsCurrency));
      ItemObj.AddPair('valor_base', TJSONNumber.Create(Query.DataSet.FieldByName('VE_VALORB').AsCurrency));
      ItemObj.AddPair('desconto', TJSONNumber.Create(Query.DataSet.FieldByName('VE_DESCONTO').AsFloat));
      ItemObj.AddPair('lucro', TJSONNumber.Create(Query.DataSet.FieldByName('VE_LUCRO').AsCurrency));

      AdicionaisArr := TJSONArray.Create;
      Aux.Clear;
      Aux.Add('SELECT ADI_NOME, ADI_VALOR VLR_UNIT, (ADI_VALOR * VA_QUANTIDADE) VLR_TOTAL, VA_QUANTIDADE');
      Aux.Add('FROM VE_ADICIONAIS JOIN ADICIONAIS ON VA_ADI = ADI_CODIGO');
      Aux.Add('WHERE VA_VE = :VEN_EST');
      Aux.AddParam('VEN_EST', Query.DataSet.FieldByName('VE_CODIGO').AsInteger);
      Aux.Open;
      Aux.DataSet.First;
      while not Aux.DataSet.Eof do
      begin
        AdicionalObj := TJSONObject.Create;
        AdicionalObj.AddPair('descricao', Aux.DataSet.FieldByName('ADI_NOME').AsString);
        AdicionalObj.AddPair('quantidade', TJSONNumber.Create(Aux.DataSet.FieldByName('VA_QUANTIDADE').AsFloat));
        AdicionalObj.AddPair('valor_unitario', TJSONNumber.Create(Aux.DataSet.FieldByName('VLR_UNIT').AsCurrency));
        AdicionalObj.AddPair('valor_total', TJSONNumber.Create(Aux.DataSet.FieldByName('VLR_TOTAL').AsCurrency));
        AdicionaisArr.AddElement(AdicionalObj);
        TotalAdicionais := TotalAdicionais + Aux.DataSet.FieldByName('VLR_TOTAL').AsCurrency;
        Aux.DataSet.Next;
      end;

      ItemObj.AddPair('adicionais', AdicionaisArr);
      ItensArr.AddElement(ItemObj);

      SubTotal := SubTotal + Query.DataSet.FieldByName('VE_VALOR').AsCurrency;
      TotalLucro := TotalLucro + Query.DataSet.FieldByName('VE_LUCRO').AsCurrency;
      Query.DataSet.Next;
    end;

    Query.Clear;
    Query.Add('SELECT COALESCE(SUM(VEN_TAXA_ENTREGA), 0) TAXA_ENTREGA FROM VENDAS');
    if Grupo > 0 then
    begin
      Query.Add('JOIN VEN_EST ON VE_VEN = VEN_CODIGO');
      Query.Add('JOIN PRODUTOS ON VE_PRO = PRO_CODIGO');
      Query.Add('JOIN GRUPOS ON GRU_CODIGO = PRO_GRU');
    end;
    if Cliente > 0 then
      Query.Add('JOIN CLIENTES ON VEN_CLI = CLI_CODIGO');
    Query.Add('WHERE VEN_DATA BETWEEN :DATA_INI AND :DATA_FIM' + SQLCliente + SQLGrupo + SQLTipo + SQLCaixa);
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    if Cliente > 0 then Query.AddParam('CLIENTE', Cliente);
    if Grupo > 0 then Query.AddParam('GRUPO', Grupo);
    if not TipoPedido.IsEmpty then Query.AddParam('TIPO_PEDIDO', TipoPedido);
    if (not TodosCaixas) and (CaixaAtual > 0) then
      Query.AddParam('CAIXA_ATUAL', CaixaAtual);
    Query.Open;
    TotalTaxaEntrega := Query.DataSet.FieldByName('TAXA_ENTREGA').AsCurrency;

    Query.Clear;
    Query.Add('SELECT COALESCE(SUM(VE_VALOR), 0) CANCELADAS FROM VENDAS JOIN VEN_EST ON VE_VEN = VEN_CODIGO');
    if Grupo > 0 then
    begin
      Query.Add('JOIN PRODUTOS ON VE_PRO = PRO_CODIGO');
      Query.Add('JOIN GRUPOS ON GRU_CODIGO = PRO_GRU');
    end;
    if Cliente > 0 then
      Query.Add('JOIN CLIENTES ON VEN_CLI = CLI_CODIGO');
    Query.Add('WHERE VEN_DATAC BETWEEN :DATA_INI AND :DATA_FIM' + SQLCliente + SQLGrupo + SQLTipo + SQLCaixaCanc);
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    if Cliente > 0 then Query.AddParam('CLIENTE', Cliente);
    if Grupo > 0 then Query.AddParam('GRUPO', Grupo);
    if not TipoPedido.IsEmpty then Query.AddParam('TIPO_PEDIDO', TipoPedido);
    if (not TodosCaixas) and (CaixaAtual > 0) then
      Query.AddParam('CAIXA_ATUAL', CaixaAtual);
    Query.Open;
    TotalCanceladas := Query.DataSet.FieldByName('CANCELADAS').AsCurrency;

    Query.Clear;
    Query.Add('SELECT REC_TIPO, TP_CONDICAO, SUM(REC_VALOR+REC_JUROS-REC_DESCONTOS) VLR_TOTAL');
    Query.Add('FROM VENDAS JOIN PED_FAT ON VEN_CODIGO = PF_COD_PED');
    Query.Add('JOIN FATURAMENTOS ON PF_FAT = FAT_CODIGO');
    Query.Add('JOIN RECEBIMENTOS ON FAT_CODIGO = REC_FAT');
    Query.Add('JOIN TIPO_PGM ON REC_CON = TP_CODIGO');
    if Cliente > 0 then
      Query.Add('JOIN CLIENTES ON CLI_CODIGO = VEN_CLI');
    Query.Add('WHERE PF_TABELA = ''VENDAS'' AND VEN_DATAC = ''01/01/1900''');
    Query.Add('  AND (REC_SITUACAO >= 0 AND REC_SITUACAO < 2)');
    Query.Add('  AND VEN_DATA BETWEEN :DATA_INI AND :DATA_FIM' + SQLCliente + SQLTipo);
    if (not TodosCaixas) and (CaixaAtual > 0) then
      Query.Add('  AND REC_CAI = :CAIXA_ATUAL')
    else if (not TodosCaixas) and (PDV > 0) and (CaixaAtual = 0) then
      Query.Add('  AND 1 = 0');
    if Grupo > 0 then
      Query.Add('  AND FAT_CODIGO IN (SELECT DISTINCT VEN_FAT FROM VENDAS JOIN VEN_EST ON VE_VEN = VEN_CODIGO JOIN PRODUTOS ON VE_PRO = PRO_CODIGO JOIN GRUPOS ON PRO_GRU = GRU_CODIGO WHERE GRU_G1 = :GRUPO)');
    Query.Add('GROUP BY REC_TIPO, TP_CONDICAO');
    Query.Add('ORDER BY REC_TIPO');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    if Cliente > 0 then Query.AddParam('CLIENTE', Cliente);
    if Grupo > 0 then Query.AddParam('GRUPO', Grupo);
    if not TipoPedido.IsEmpty then Query.AddParam('TIPO_PEDIDO', TipoPedido);
    if (not TodosCaixas) and (CaixaAtual > 0) then
      Query.AddParam('CAIXA_ATUAL', CaixaAtual);
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      ResumoObj := TJSONObject.Create;
      ResumoObj.AddPair('tipo', Query.DataSet.FieldByName('REC_TIPO').AsString);
      ResumoObj.AddPair('condicao', Query.DataSet.FieldByName('TP_CONDICAO').AsString);
      ResumoObj.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('VLR_TOTAL').AsCurrency));
      ResumoArr.AddElement(ResumoObj);
      if UpperCase(Query.DataSet.FieldByName('TP_CONDICAO').AsString) = 'P' then
        TotalPrazo := TotalPrazo + Query.DataSet.FieldByName('VLR_TOTAL').AsCurrency
      else
        TotalVista := TotalVista + Query.DataSet.FieldByName('VLR_TOTAL').AsCurrency;
      Query.DataSet.Next;
    end;

    TotalGeral := SubTotal + TotalAdicionais + TotalTaxaEntrega;

    PeriodoObj.AddPair('data_inicio', FormatDateTime('yyyy-mm-dd', DataInicio));
    PeriodoObj.AddPair('data_fim', FormatDateTime('yyyy-mm-dd', DataFim));
    PeriodoObj.AddPair('cliente', TJSONNumber.Create(Cliente));
    PeriodoObj.AddPair('grupo', TJSONNumber.Create(Grupo));
    PeriodoObj.AddPair('tipo_pedido', TipoPedido);
    PeriodoObj.AddPair('pdv', TJSONNumber.Create(PDV));
    PeriodoObj.AddPair('caixa', TJSONNumber.Create(CaixaAtual));
    PeriodoObj.AddPair('todos_caixas', TJSONBool.Create(TodosCaixas));

    TotaisObj.AddPair('subtotal', TJSONNumber.Create(SubTotal));
    TotaisObj.AddPair('adicionais', TJSONNumber.Create(TotalAdicionais));
    TotaisObj.AddPair('taxa_entrega', TJSONNumber.Create(TotalTaxaEntrega));
    TotaisObj.AddPair('canceladas', TJSONNumber.Create(TotalCanceladas));
    TotaisObj.AddPair('venda_vista', TJSONNumber.Create(TotalVista));
    TotaisObj.AddPair('venda_prazo', TJSONNumber.Create(TotalPrazo));
    TotaisObj.AddPair('lucro', TJSONNumber.Create(TotalLucro));
    TotaisObj.AddPair('total', TJSONNumber.Create(TotalGeral));

    DataObj.AddPair('periodo', PeriodoObj);
    DataObj.AddPair('totais', TotaisObj);
    DataObj.AddPair('vendas', VendasArr);
    DataObj.AddPair('resumo_pagamentos', ResumoArr);
    DataObj.AddPair('caixa_atual', TJSONNumber.Create(CaixaAtual));
    DataObj.AddPair('pdv', TJSONNumber.Create(PDV));
    DataObj.AddPair('modo_todos_caixas', TJSONBool.Create(TodosCaixas));

    Res.Status(THTTPStatus.OK)
      .Send<TJSONObject>(SuccessResponse(DataObj, 'Relatorio analitico de vendas carregado com sucesso.'));
  except
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError)
        .Send<TJSONObject>(ErrorResponse('Falha ao carregar relatorio analitico de vendas.', 'INTERNAL_ERROR', E.Message));
  end;
end;

class procedure TRelatoriosController.Resumo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  DataInicio, DataFim: TDate;
  PDV: Integer;
  QuantidadeVendas: Integer;
  TotalVendas: Currency;
  TicketMedio: Currency;
  TotalCredito, TotalDebito, Saldo: Currency;
  DataObj, PeriodoObj, ResumoVendasObj, ResumoCaixaObj: TJSONObject;
  VendasPorDiaArr, TopProdutosArr: TJSONArray;
  Item: TJSONObject;
begin
  DataInicio := Date - 7;
  DataFim := Date;
  PDV := 0;

  if Req.Query.ContainsKey('dataInicio') and
     (not ParseDateParam(Req.Query.Items['dataInicio'], DataInicio)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro dataInicio invalido. Use yyyy-mm-dd.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if Req.Query.ContainsKey('dataFim') and
     (not ParseDateParam(Req.Query.Items['dataFim'], DataFim)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro dataFim invalido. Use yyyy-mm-dd.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if Req.Query.ContainsKey('pdv') and
     (not TryStrToInt(Req.Query.Items['pdv'], PDV)) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Parametro pdv invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if DataFim < DataInicio then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('dataFim nao pode ser menor que dataInicio.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Query := TDatabase.Query;
  DataObj := TJSONObject.Create;
  PeriodoObj := TJSONObject.Create;
  ResumoVendasObj := TJSONObject.Create;
  ResumoCaixaObj := TJSONObject.Create;
  VendasPorDiaArr := TJSONArray.Create;
  TopProdutosArr := TJSONArray.Create;

  try
    Query.Clear;
    Query.Add('SELECT COUNT(V.VEN_CODIGO) QTD, COALESCE(SUM(V.VEN_VALOR), 0) TOTAL');
    Query.Add('FROM VENDAS V');
    Query.Add('WHERE V.VEN_DATA BETWEEN :DATA_INI AND :DATA_FIM');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.Open;

    QuantidadeVendas := Query.DataSet.FieldByName('QTD').AsInteger;
    TotalVendas := Query.DataSet.FieldByName('TOTAL').AsCurrency;

    if QuantidadeVendas > 0 then
      TicketMedio := TotalVendas / QuantidadeVendas
    else
      TicketMedio := 0;

    Query.Clear;
    Query.Add('SELECT COALESCE(SUM(M.MOV_CREDITO), 0) TOTAL_CREDITO,');
    Query.Add('       COALESCE(SUM(M.MOV_DEBITO), 0) TOTAL_DEBITO');
    Query.Add('FROM MOVIMENTACOES M');
    Query.Add('LEFT JOIN CAIXA C ON C.CAI_CODIGO = M.MOV_CAI');
    Query.Add('WHERE M.MOV_CON = 0 AND M.MOV_DATA BETWEEN :DATA_INI AND :DATA_FIM');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.Open;

    TotalCredito := Query.DataSet.FieldByName('TOTAL_CREDITO').AsCurrency;
    TotalDebito := Query.DataSet.FieldByName('TOTAL_DEBITO').AsCurrency;
    Saldo := TotalCredito - TotalDebito;

    Query.Clear;
    Query.Add('SELECT V.VEN_DATA, COUNT(V.VEN_CODIGO) QTD, COALESCE(SUM(V.VEN_VALOR), 0) TOTAL');
    Query.Add('FROM VENDAS V');
    Query.Add('WHERE V.VEN_DATA BETWEEN :DATA_INI AND :DATA_FIM');
    Query.Add('GROUP BY V.VEN_DATA');
    Query.Add('ORDER BY V.VEN_DATA');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('data', FormatDateTime('yyyy-mm-dd', Query.DataSet.FieldByName('VEN_DATA').AsDateTime));
      Item.AddPair('quantidade', TJSONNumber.Create(Query.DataSet.FieldByName('QTD').AsInteger));
      Item.AddPair('total', TJSONNumber.Create(Query.DataSet.FieldByName('TOTAL').AsCurrency));
      VendasPorDiaArr.AddElement(Item);
      Query.DataSet.Next;
    end;

    Query.Clear;
    Query.Add('SELECT FIRST 5 P.PRO_CODIGO, P.PRO_NOME,');
    Query.Add('       COALESCE(SUM(VE.VE_QUANTIDADE), 0) QUANTIDADE,');
    Query.Add('       COALESCE(SUM(VE.VE_VALOR * VE.VE_QUANTIDADE), 0) TOTAL');
    Query.Add('FROM VEN_EST VE');
    Query.Add('JOIN VENDAS V ON V.VEN_CODIGO = VE.VE_VEN');
    Query.Add('JOIN PRODUTOS P ON P.PRO_CODIGO = VE.VE_PRO');
    Query.Add('WHERE V.VEN_DATA BETWEEN :DATA_INI AND :DATA_FIM');
    Query.Add('GROUP BY P.PRO_CODIGO, P.PRO_NOME');
    Query.Add('ORDER BY TOTAL DESC');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
      Item.AddPair('descricao', Query.DataSet.FieldByName('PRO_NOME').AsString);
      Item.AddPair('quantidade', TJSONNumber.Create(Query.DataSet.FieldByName('QUANTIDADE').AsFloat));
      Item.AddPair('total', TJSONNumber.Create(Query.DataSet.FieldByName('TOTAL').AsCurrency));
      TopProdutosArr.AddElement(Item);
      Query.DataSet.Next;
    end;

    PeriodoObj.AddPair('data_inicio', FormatDateTime('yyyy-mm-dd', DataInicio));
    PeriodoObj.AddPair('data_fim', FormatDateTime('yyyy-mm-dd', DataFim));
    PeriodoObj.AddPair('pdv', TJSONNumber.Create(PDV));

    ResumoVendasObj.AddPair('quantidade_vendas', TJSONNumber.Create(QuantidadeVendas));
    ResumoVendasObj.AddPair('total_vendas', TJSONNumber.Create(TotalVendas));
    ResumoVendasObj.AddPair('ticket_medio', TJSONNumber.Create(TicketMedio));

    ResumoCaixaObj.AddPair('total_credito', TJSONNumber.Create(TotalCredito));
    ResumoCaixaObj.AddPair('total_debito', TJSONNumber.Create(TotalDebito));
    ResumoCaixaObj.AddPair('saldo', TJSONNumber.Create(Saldo));

    DataObj.AddPair('periodo', PeriodoObj);
    DataObj.AddPair('resumo_vendas', ResumoVendasObj);
    DataObj.AddPair('resumo_caixa', ResumoCaixaObj);
    DataObj.AddPair('vendas_por_dia', VendasPorDiaArr);
    DataObj.AddPair('top_produtos', TopProdutosArr);

    Res.Status(THTTPStatus.OK)
      .Send<TJSONObject>(SuccessResponse(DataObj, 'Resumo de relatorios carregado com sucesso.'));
  except
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError)
        .Send<TJSONObject>(ErrorResponse('Falha ao carregar resumo de relatorios.', 'INTERNAL_ERROR', E.Message));
  end;
end;

class procedure TRelatoriosController.Registrar;
begin
  THorse.Get('/v1/relatorios/resumo', Resumo);
  THorse.Get('/v1/relatorios/vendas-analitico', VendasAnalitico);
end;

initialization
  Swagger
    .Path('relatorios/resumo')
      .Tag('relatorios')
      .GET('Resumo de Relatorios', 'Retorna resumo consolidado de vendas e caixa por periodo e PDV')
        .AddParamQuery('dataInicio', 'Data inicial')
        	.Schema(SWAG_STRING).&End
        .AddParamQuery('dataFim', 'Data Final')
        	.Schema(SWAG_STRING).&End
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End
    .Path('relatorios/vendas-analitico')
      .Tag('relatorios')
      .GET('Vendas Analitico', 'Retorna relatorio analitico de vendas por periodo')
      	.AddParamQuery('dataInicio', 'Data inicial')
        	.Schema(SWAG_STRING).&End
        .AddParamQuery('dataFim', 'Data Final')
        	.Schema(SWAG_STRING).&End
        .AddParamQuery('pdv', 'Numero do PDV')
        	.Schema(SWAG_INTEGER).&End
        .AddParamQuery('todosCaixas', 'Se true, traz vendas de todos os caixas')
        	.Schema(SWAG_STRING).&End
        .AddParamQuery('caixa', 'Codigo especifico do caixa')
        	.Schema(SWAG_INTEGER).&End
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End;

end.
