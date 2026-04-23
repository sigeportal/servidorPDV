unit FluxoCaixa.Controller;

interface

uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  System.SysUtils,
  System.JSON,
  UnitConnection.Model.Interfaces;

type
  TFluxoCaixaController = class
  private
    class function SuccessResponse(AData: TJSONValue; const AMessage: string = ''): TJSONObject; static;
    class function ErrorResponse(const AMessage, ACode: string; const ADetails: string = ''): TJSONObject; static;
  public
    class procedure Registrar;
    class procedure Listar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Lancar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  end;

implementation

uses
  UnitDatabase,
  UnitFunctions;

class function TFluxoCaixaController.SuccessResponse(AData: TJSONValue; const AMessage: string): TJSONObject;
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

class function TFluxoCaixaController.ErrorResponse(const AMessage, ACode, ADetails: string): TJSONObject;
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

class procedure TFluxoCaixaController.Listar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  DataInicio, DataFim: TDate;
  PDV: Integer;
  Itens, DataObj: TJSONObject;
  Lista: TJSONArray;
  Item: TJSONObject;
  TotalCredito, TotalDebito, Saldo: Currency;
begin
  Query := TDatabase.Query;
  Lista := TJSONArray.Create;
  DataObj := TJSONObject.Create;
  try
    DataInicio := Date - 7;
    DataFim := Date;
    PDV := 1;

    if Req.Query.ContainsKey('dataInicio') then
      DataInicio := StrToDate(Req.Query.Items['dataInicio']);
    if Req.Query.ContainsKey('dataFim') then
      DataFim := StrToDate(Req.Query.Items['dataFim']);
    if Req.Query.ContainsKey('pdv') then
      PDV := Req.Query.Items['pdv'].ToInteger;

    Query.Clear;
    Query.Add('SELECT M.MOV_CODIGO, M.MOV_DATA, M.MOV_DATAHORA, M.MOV_DESCRICAO, M.MOV_NOME,');
    Query.Add('COALESCE(M.MOV_CREDITO, 0) MOV_CREDITO, COALESCE(M.MOV_DEBITO, 0) MOV_DEBITO,');
    Query.Add('COALESCE(C.CAI_PDV, 0) CAI_PDV');
    Query.Add('FROM MOVIMENTACOES M');
    Query.Add('LEFT JOIN CAIXA C ON C.CAI_CODIGO = M.MOV_CAI');
    Query.Add('WHERE M.MOV_CON = 0 AND M.MOV_DATA BETWEEN :DATA_INI AND :DATA_FIM');
    Query.Add('  AND (:PDV_FILTRO = 0 OR C.CAI_PDV = :PDV_VALOR)');
    Query.Add('ORDER BY M.MOV_DATAHORA DESC, M.MOV_CODIGO DESC');
    Query.AddParam('DATA_INI', FormatDateTime('dd.mm.yyyy', DataInicio));
    Query.AddParam('DATA_FIM', FormatDateTime('dd.mm.yyyy', DataFim));
    Query.AddParam('PDV_FILTRO', PDV);
    Query.AddParam('PDV_VALOR', PDV);
    Query.Open;

    TotalCredito := 0;
    TotalDebito := 0;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('MOV_CODIGO').AsInteger));
      Item.AddPair('data', FormatDateTime('yyyy-mm-dd', Query.DataSet.FieldByName('MOV_DATA').AsDateTime));
      Item.AddPair('data_hora', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Query.DataSet.FieldByName('MOV_DATAHORA').AsDateTime));
      Item.AddPair('descricao', Query.DataSet.FieldByName('MOV_DESCRICAO').AsString);
      Item.AddPair('nome', Query.DataSet.FieldByName('MOV_NOME').AsString);
      Item.AddPair('credito', TJSONNumber.Create(Query.DataSet.FieldByName('MOV_CREDITO').AsCurrency));
      Item.AddPair('debito', TJSONNumber.Create(Query.DataSet.FieldByName('MOV_DEBITO').AsCurrency));
      Item.AddPair('pdv', TJSONNumber.Create(Query.DataSet.FieldByName('CAI_PDV').AsInteger));
      Lista.AddElement(Item);

      TotalCredito := TotalCredito + Query.DataSet.FieldByName('MOV_CREDITO').AsCurrency;
      TotalDebito := TotalDebito + Query.DataSet.FieldByName('MOV_DEBITO').AsCurrency;
      Query.DataSet.Next;
    end;

    Saldo := TotalCredito - TotalDebito;

    Itens := TJSONObject.Create;
    Itens.AddPair('total_credito', TJSONNumber.Create(TotalCredito));
    Itens.AddPair('total_debito', TJSONNumber.Create(TotalDebito));
    Itens.AddPair('saldo', TJSONNumber.Create(Saldo));

    DataObj.AddPair('totais', Itens);
    DataObj.AddPair('itens', Lista);

    Res.Status(THTTPStatus.OK).Send<TJSONObject>(SuccessResponse(DataObj, 'Fluxo de caixa carregado com sucesso.'));
  except
    on EConvertError do
      Res.Status(THTTPStatus.BadRequest)
        .Send<TJSONObject>(ErrorResponse('Parametro de data invalido. Use yyyy-mm-dd.', 'VALIDATION_ERROR'));
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError)
        .Send<TJSONObject>(ErrorResponse('Falha ao carregar fluxo de caixa.', 'INTERNAL_ERROR', E.Message));
  end;
end;

class procedure TFluxoCaixaController.Lancar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Body, DataObj: TJSONObject;
  Tipo: string;
  Valor: Currency;
  Descricao: string;
  PDV, CodigoMov, CodigoCaixa: Integer;
  Credito, Debito, SaldoAtual: Currency;
  PlanoConta, NomeMov: string;
begin
  Body := Req.Body<TJSONObject>;
  if not Assigned(Body) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Body da operacao nao informado.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Tipo := UpperCase(Trim(Body.GetValue<string>('tipo', '')));
  Valor := Body.GetValue<Currency>('valor', 0);
  Descricao := Trim(Body.GetValue<string>('descricao', ''));
  PDV := Body.GetValue<Integer>('pdv', 1);

  if (Tipo <> 'SUPRIMENTO') and (Tipo <> 'SANGRIA') then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Tipo invalido. Use SUPRIMENTO ou SANGRIA.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if Valor <= 0 then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Valor deve ser maior que zero.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Query := TDatabase.Query;
  try
    Query.Clear;
    Query.Add('SELECT COALESCE(SUM(M.MOV_CREDITO - M.MOV_DEBITO), 0) SALDO');
    Query.Add('FROM MOVIMENTACOES M');
    Query.Add('LEFT JOIN CAIXA C ON C.CAI_CODIGO = M.MOV_CAI');
    Query.Add('WHERE M.MOV_CON = 0 AND (:PDV_FILTRO = 0 OR C.CAI_PDV = :PDV_VALOR)');
    Query.AddParam('PDV_FILTRO', PDV);
    Query.AddParam('PDV_VALOR', PDV);
    Query.Open;
    SaldoAtual := Query.DataSet.FieldByName('SALDO').AsCurrency;

    if (Tipo = 'SANGRIA') and (Valor > SaldoAtual) then
    begin
      Res.Status(THTTPStatus.Conflict)
        .Send<TJSONObject>(ErrorResponse('Valor de sangria maior que saldo disponivel.', 'CONFLICT'));
      Exit;
    end;

    Query.Clear;
    Query.Add('SELECT FIRST 1 CAI_CODIGO FROM CAIXA WHERE CAI_PDV = :PDV ORDER BY CAI_CODIGO DESC');
    Query.AddParam('PDV', PDV);
    Query.Open;
    if Query.DataSet.IsEmpty then
      CodigoCaixa := 0
    else
      CodigoCaixa := Query.DataSet.FieldByName('CAI_CODIGO').AsInteger;

    CodigoMov := IncrementaGenerator('GEN_MOV');

    if Tipo = 'SUPRIMENTO' then
    begin
      Credito := Valor;
      Debito := 0;
      PlanoConta := '6.9';
      if Descricao.IsEmpty then
        Descricao := 'SUPRIMENTO PDV ' + IntToStr(PDV);
    end
    else
    begin
      Credito := 0;
      Debito := Valor;
      PlanoConta := '7.9';
      if Descricao.IsEmpty then
        Descricao := 'SANGRIA PDV ' + IntToStr(PDV);
    end;

    NomeMov := Copy(Descricao, 1, 30);

    Query.Clear;
    Query.Add('INSERT INTO MOVIMENTACOES (');
    Query.Add('  MOV_CODIGO, MOV_CREDITO, MOV_DEBITO, MOV_DESCRICAO, MOV_TIPO, MOV_DATA, MOV_CON,');
    Query.Add('  MOV_DATAHORA, MOV_ORDENA, MOV_PLANO, MOV_NOME, MOV_CAI, MOV_ESTADO, MOV_TROCO');
    Query.Add(') VALUES (');
    Query.Add('  :CODIGO, :CREDITO, :DEBITO, :DESCRICAO, :TIPO, CURRENT_DATE, 0,');
    Query.Add('  :DATAHORA, :ORDENA, :PLANO, :NOME, :CAI, :ESTADO, 0');
    Query.Add(')');
    Query.AddParam('CODIGO', CodigoMov);
    Query.AddParam('CREDITO', Credito);
    Query.AddParam('DEBITO', Debito);
    Query.AddParam('DESCRICAO', Copy(Descricao, 1, 80));
    Query.AddParam('TIPO', 1);
    Query.AddParam('DATAHORA', Now);
    Query.AddParam('ORDENA', CodigoMov);
    Query.AddParam('PLANO', PlanoConta);
    Query.AddParam('NOME', NomeMov);
    Query.AddParam('CAI', CodigoCaixa);
    Query.AddParam('ESTADO', 'A');
    Query.ExecSQL;

    DataObj := TJSONObject.Create;
    DataObj.AddPair('codigo', TJSONNumber.Create(CodigoMov));
    DataObj.AddPair('tipo', Tipo);
    DataObj.AddPair('valor', TJSONNumber.Create(Valor));
    DataObj.AddPair('descricao', Copy(Descricao, 1, 80));
    DataObj.AddPair('pdv', TJSONNumber.Create(PDV));
    DataObj.AddPair('caixa', TJSONNumber.Create(CodigoCaixa));

    Res.Status(THTTPStatus.Created)
      .Send<TJSONObject>(SuccessResponse(DataObj, 'Lancamento registrado com sucesso.'));
  except
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError)
        .Send<TJSONObject>(ErrorResponse('Falha ao registrar lancamento.', 'INTERNAL_ERROR', E.Message));
  end;
end;

class procedure TFluxoCaixaController.Registrar;
begin
  THorse.Get('/v1/fluxo-caixa', Listar);
  THorse.Post('/v1/fluxo-caixa/lancamentos', Lancar);
end;

initialization
  Swagger
    .Path('fluxo-caixa')
      .Tag('fluxo-caixa')
      .GET('Lista Fluxo de Caixa', 'Lista lancamentos do fluxo de caixa por periodo e PDV')
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End
    .Path('fluxo-caixa/lancamentos')
      .Tag('fluxo-caixa')
      .POST('Lancar Sangria/Suprimento', 'Registra lancamento manual de caixa')
        .AddResponse(201, 'Created').&End
        .AddResponse(400).&End
        .AddResponse(409).&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End;

end.
