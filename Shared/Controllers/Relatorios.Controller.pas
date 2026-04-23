unit Relatorios.Controller;

interface

uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  UnitConnection.Model.Interfaces;

type
  TRelatoriosController = class
  private
    class function SuccessResponse(AData: TJSONValue; const AMessage: string = ''): TJSONObject; static;
    class function ErrorResponse(const AMessage, ACode: string; const ADetails: string = ''): TJSONObject; static;
    class function ParseDateParam(const AValue: string; out ADate: TDate): Boolean; static;
  public
    class procedure Registrar;
    class procedure Resumo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
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
  if TryISO8601ToDate(AValue, DateTimeValue, False) then
  begin
    ADate := DateOf(DateTimeValue);
    Exit(True);
  end;

  FS := TFormatSettings.Create;
  FS.DateSeparator := '/';
  FS.ShortDateFormat := 'dd/mm/yyyy';

  Result := TryStrToDate(AValue, DateTimeValue, FS);
  if Result then
    ADate := DateOf(DateTimeValue);
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
    Query.Add('  AND (:PDV_FILTRO = 0 OR V.VEN_PDV = :PDV_VALOR)');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.AddParam('PDV_FILTRO', PDV);
    Query.AddParam('PDV_VALOR', PDV);
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
    Query.Add('  AND (:PDV_FILTRO = 0 OR C.CAI_PDV = :PDV_VALOR)');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.AddParam('PDV_FILTRO', PDV);
    Query.AddParam('PDV_VALOR', PDV);
    Query.Open;

    TotalCredito := Query.DataSet.FieldByName('TOTAL_CREDITO').AsCurrency;
    TotalDebito := Query.DataSet.FieldByName('TOTAL_DEBITO').AsCurrency;
    Saldo := TotalCredito - TotalDebito;

    Query.Clear;
    Query.Add('SELECT V.VEN_DATA, COUNT(V.VEN_CODIGO) QTD, COALESCE(SUM(V.VEN_VALOR), 0) TOTAL');
    Query.Add('FROM VENDAS V');
    Query.Add('WHERE V.VEN_DATA BETWEEN :DATA_INI AND :DATA_FIM');
    Query.Add('  AND (:PDV_FILTRO = 0 OR V.VEN_PDV = :PDV_VALOR)');
    Query.Add('GROUP BY V.VEN_DATA');
    Query.Add('ORDER BY V.VEN_DATA');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.AddParam('PDV_FILTRO', PDV);
    Query.AddParam('PDV_VALOR', PDV);
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
    Query.Add('SELECT FIRST 5 P.PRO_CODIGO, P.PRO_DESCRICAO,');
    Query.Add('       COALESCE(SUM(VE.VE_QUANTIDADE), 0) QUANTIDADE,');
    Query.Add('       COALESCE(SUM(VE.VE_VALOR * VE.VE_QUANTIDADE), 0) TOTAL');
    Query.Add('FROM VEN_EST VE');
    Query.Add('JOIN VENDAS V ON V.VEN_CODIGO = VE.VE_VEN');
    Query.Add('JOIN PRODUTOS P ON P.PRO_CODIGO = VE.VE_PRO');
    Query.Add('WHERE V.VEN_DATA BETWEEN :DATA_INI AND :DATA_FIM');
    Query.Add('  AND (:PDV_FILTRO = 0 OR V.VEN_PDV = :PDV_VALOR)');
    Query.Add('GROUP BY P.PRO_CODIGO, P.PRO_DESCRICAO');
    Query.Add('ORDER BY TOTAL DESC');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.AddParam('PDV_FILTRO', PDV);
    Query.AddParam('PDV_VALOR', PDV);
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
      Item.AddPair('descricao', Query.DataSet.FieldByName('PRO_DESCRICAO').AsString);
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
end;

initialization
  Swagger
    .Path('relatorios/resumo')
      .Tag('relatorios')
      .GET('Resumo de Relatorios', 'Retorna resumo consolidado de vendas e caixa por periodo e PDV')
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End;

end.
