unit Estoque.Controller;

interface

uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  System.SysUtils,
  System.JSON,
  UnitConnection.Model.Interfaces;

type
  TEstoqueController = class
  private
    class function SuccessResponse(AData: TJSONValue; const AMessage: string = ''): TJSONObject; static;
    class function ErrorResponse(const AMessage, ACode: string; const ADetails: string = ''): TJSONObject; static;
  public
    class procedure Registrar;
    class procedure Listar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Historico(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Ajustar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  end;

implementation

uses
  UnitDatabase,
  UnitFunctions;

class function TEstoqueController.SuccessResponse(AData: TJSONValue; const AMessage: string): TJSONObject;
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

class function TEstoqueController.ErrorResponse(const AMessage, ACode, ADetails: string): TJSONObject;
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

class procedure TEstoqueController.Listar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Busca: string;
  Data: TJSONArray;
  Item: TJSONObject;
begin
  Query := TDatabase.Query;
  Data := TJSONArray.Create;
  try
    Busca := UpperCase(Trim(Req.Query.Items['busca']));

    Query.Clear;
    Query.Add('SELECT FIRST 300');
    Query.Add('  PRO_CODIGO, PRO_NOME, COALESCE(PRO_QUANTIDADE, 0) PRO_QUANTIDADE,');
    Query.Add('  COALESCE(PRO_VALORV, 0) PRO_VALORV, COALESCE(PRO_ESTADO, '''') PRO_ESTADO');
    Query.Add('FROM PRODUTOS');
    Query.Add('WHERE (PRO_ESTADO IS NULL OR PRO_ESTADO <> ''INATIVO'')');
    if not Busca.IsEmpty then
    begin
      Query.Add('  AND (UPPER(PRO_NOME) LIKE :BUSCA OR CAST(PRO_CODIGO AS VARCHAR(20)) LIKE :BUSCA_CODIGO OR UPPER(PRO_CODBARRA) LIKE :BUSCA_BARRAS)');
      Query.AddParam('BUSCA', '%' + Busca + '%');
      Query.AddParam('BUSCA_CODIGO', '%' + Busca + '%');
      Query.AddParam('BUSCA_BARRAS', '%' + Busca + '%');
    end;
    Query.Add('ORDER BY PRO_NOME');
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
      Item.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
      Item.AddPair('quantidade', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_QUANTIDADE').AsFloat));
      Item.AddPair('valor', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_VALORV').AsCurrency));
      Item.AddPair('estado', Query.DataSet.FieldByName('PRO_ESTADO').AsString);
      Data.AddElement(Item);
      Query.DataSet.Next;
    end;

    Res.Status(THTTPStatus.OK).Send<TJSONObject>(SuccessResponse(Data, 'Estoque carregado com sucesso.'));
  except
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError)
        .Send<TJSONObject>(ErrorResponse('Falha ao carregar estoque.', 'INTERNAL_ERROR', E.Message));
  end;
end;

class procedure TEstoqueController.Historico(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Codigo: Integer;
  Data: TJSONArray;
  Item: TJSONObject;
begin
  if not Req.Params.ContainsKey('codigo') then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Codigo do produto e obrigatorio.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Codigo := Req.Params.Items['codigo'].ToInteger;
  Query := TDatabase.Query;
  Data := TJSONArray.Create;
  try
    Query.Clear;
    Query.Add('SELECT FIRST 100');
    Query.Add('  HP_CODIGO, HP_DATA, HP_ORIGEM, HP_DOC, HP_QUANTIDADE, HP_TIPO, HP_QUANTIDADEA');
    Query.Add('FROM HIS_PRO');
    Query.Add('WHERE HP_PRO = :PRO');
    Query.Add('ORDER BY HP_CODIGO DESC');
    Query.AddParam('PRO', Codigo);
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('HP_CODIGO').AsInteger));
      Item.AddPair('data', FormatDateTime('yyyy-mm-dd', Query.DataSet.FieldByName('HP_DATA').AsDateTime));
      Item.AddPair('origem', Query.DataSet.FieldByName('HP_ORIGEM').AsString);
      Item.AddPair('documento', Query.DataSet.FieldByName('HP_DOC').AsString);
      Item.AddPair('quantidade', TJSONNumber.Create(Query.DataSet.FieldByName('HP_QUANTIDADE').AsFloat));
      Item.AddPair('tipo', Query.DataSet.FieldByName('HP_TIPO').AsString);
      Item.AddPair('quantidade_apos', TJSONNumber.Create(Query.DataSet.FieldByName('HP_QUANTIDADEA').AsFloat));
      Data.AddElement(Item);
      Query.DataSet.Next;
    end;

    Res.Status(THTTPStatus.OK).Send<TJSONObject>(SuccessResponse(Data, 'Historico carregado com sucesso.'));
  except
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError)
        .Send<TJSONObject>(ErrorResponse('Falha ao carregar historico do produto.', 'INTERNAL_ERROR', E.Message));
  end;
end;

class procedure TEstoqueController.Ajustar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Body: TJSONObject;
  Codigo: Integer;
  Quantidade, QuantidadeAtual, QuantidadeNova: Double;
  Tipo, Origem, Documento: string;
  ValorC, ValorV, ValorCM, ValorOP, ValorM: Currency;
  CodHis: Integer;
  ResultData: TJSONObject;
begin
  if not Req.Params.ContainsKey('codigo') then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Codigo do produto e obrigatorio.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Body := Req.Body<TJSONObject>;
  if not Assigned(Body) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Body do ajuste nao informado.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Codigo := Req.Params.Items['codigo'].ToInteger;
  Quantidade := Body.GetValue<Double>('quantidade', 0);
  Tipo := UpperCase(Trim(Body.GetValue<string>('tipo', 'E')));
  Origem := Trim(Body.GetValue<string>('origem', 'AJUSTE_MANUAL'));
  Documento := Trim(Body.GetValue<string>('documento', 'AJUSTE-PDV'));

  if Quantidade <= 0 then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Quantidade deve ser maior que zero.', 'VALIDATION_ERROR'));
    Exit;
  end;

  if (Tipo <> 'E') and (Tipo <> 'S') then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Tipo de ajuste invalido. Use E ou S.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Query := TDatabase.Query;
  try
    Query.Clear;
    Query.Add('SELECT PRO_QUANTIDADE, PRO_VALORC, PRO_VALORV, PRO_VALORCM, PRO_VALORL, PRO_VALORF');
    Query.Add('FROM PRODUTOS');
    Query.Add('WHERE PRO_CODIGO = :CODIGO');
    Query.AddParam('CODIGO', Codigo);
    Query.Open;

    if Query.DataSet.IsEmpty then
    begin
      Res.Status(THTTPStatus.NotFound)
        .Send<TJSONObject>(ErrorResponse('Produto nao encontrado.', 'NOT_FOUND'));
      Exit;
    end;

    QuantidadeAtual := Query.DataSet.FieldByName('PRO_QUANTIDADE').AsFloat;
    ValorC := Query.DataSet.FieldByName('PRO_VALORC').AsCurrency;
    ValorV := Query.DataSet.FieldByName('PRO_VALORV').AsCurrency;
    ValorCM := Query.DataSet.FieldByName('PRO_VALORCM').AsCurrency;
    ValorOP := Query.DataSet.FieldByName('PRO_VALORL').AsCurrency;
    ValorM := Query.DataSet.FieldByName('PRO_VALORF').AsCurrency;

    if Tipo = 'E' then
      QuantidadeNova := QuantidadeAtual + Quantidade
    else
      QuantidadeNova := QuantidadeAtual - Quantidade;

    if QuantidadeNova < 0 then
    begin
      Res.Status(THTTPStatus.Conflict)
        .Send<TJSONObject>(ErrorResponse('Ajuste resultaria em estoque negativo.', 'CONFLICT'));
      Exit;
    end;

    Query.Clear;
    Query.Add('UPDATE PRODUTOS SET PRO_QUANTIDADE = :QTD, PRO_DATAUA = CURRENT_DATE');
    Query.Add('WHERE PRO_CODIGO = :CODIGO');
    Query.AddParam('QTD', QuantidadeNova);
    Query.AddParam('CODIGO', Codigo);
    Query.ExecSQL;

    CodHis := IncrementaGenerator('GEN_HP');
    Query.Clear;
    Query.Add('INSERT INTO HIS_PRO (');
    Query.Add('  HP_CODIGO, HP_DATA, HP_PRO, HP_ORIGEM, HP_DOC, HP_QUANTIDADE,');
    Query.Add('  HP_VALORC, HP_VALORV, HP_VALORCM, HP_VALOROP, HP_VALORM, HP_TIPO, HP_TIPO2, HP_QUANTIDADEA');
    Query.Add(') VALUES (');
    Query.Add('  :CODIGO, CURRENT_DATE, :PRO, :ORIGEM, :DOC, :QTD,');
    Query.Add('  :VALORC, :VALORV, :VALORCM, :VALOROP, :VALORM, :TIPO, :TIPO2, :QTD_A');
    Query.Add(')');
    Query.AddParam('CODIGO', CodHis);
    Query.AddParam('PRO', Codigo);
    Query.AddParam('ORIGEM', Origem);
    Query.AddParam('DOC', Documento);
    Query.AddParam('QTD', Quantidade);
    Query.AddParam('VALORC', ValorC);
    Query.AddParam('VALORV', ValorV);
    Query.AddParam('VALORCM', ValorCM);
    Query.AddParam('VALOROP', ValorOP);
    Query.AddParam('VALORM', ValorM);
    Query.AddParam('TIPO', Tipo);
    Query.AddParam('TIPO2', 0);
    Query.AddParam('QTD_A', QuantidadeNova);
    Query.ExecSQL;

    ResultData := TJSONObject.Create;
    ResultData.AddPair('produto', TJSONNumber.Create(Codigo));
    ResultData.AddPair('tipo', Tipo);
    ResultData.AddPair('quantidade_ajuste', TJSONNumber.Create(Quantidade));
    ResultData.AddPair('quantidade_anterior', TJSONNumber.Create(QuantidadeAtual));
    ResultData.AddPair('quantidade_atual', TJSONNumber.Create(QuantidadeNova));
    ResultData.AddPair('historico_codigo', TJSONNumber.Create(CodHis));

    Res.Status(THTTPStatus.OK)
      .Send<TJSONObject>(SuccessResponse(ResultData, 'Ajuste de estoque realizado com sucesso.'));
  except
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError)
        .Send<TJSONObject>(ErrorResponse('Falha ao ajustar estoque.', 'INTERNAL_ERROR', E.Message));
  end;
end;

class procedure TEstoqueController.Registrar;
begin
  THorse.Get('/v1/estoque', Listar);
  THorse.Get('/v1/estoque/:codigo/historico', Historico);
  THorse.Post('/v1/estoque/:codigo/ajuste', Ajustar);
end;

initialization
  Swagger
    .Path('estoque')
      .Tag('estoque')
      .GET('Lista Estoque', 'Lista produtos para consulta e ajuste de estoque')
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End
    .Path('estoque/{codigo}/historico')
      .Tag('estoque')
      .GET('Historico do Produto', 'Retorna historico de movimentacoes de estoque de um produto')
        .AddParamPath('codigo', 'Codigo do produto').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(404).&End
        .AddResponse(500).&End
      .&End
    .&End
    .Path('estoque/{codigo}/ajuste')
      .Tag('estoque')
      .POST('Ajustar Estoque', 'Ajusta quantidade do produto e registra historico')
        .AddParamPath('codigo', 'Codigo do produto').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(404).&End
        .AddResponse(409).&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End;

end.
