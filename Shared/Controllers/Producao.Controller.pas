unit Producao.Controller;

interface

uses
  Horse,
  Horse.Commons,
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

type
  TProducaoController = class
  private
    class function SuccessResponse(AData: TJSONValue; const AMessage: string = ''): TJSONObject; static;
    class function ErrorResponse(const AMessage, ACode: string; const ADetails: string = ''): TJSONObject; static;
    class function ProximoGen(Conn: TFDConnection; Trans: TFDTransaction; const NomeGen: string): Integer; static;
    class function NormalizarTipoAlvo(const Tipo: string): string; static;
    class function BuscarDadosAlvo(Conn: TFDConnection; Trans: TFDTransaction; const TipoAlvo: string; CodAlvo: Integer; out NomeAlvo: string; out PrecoVenda: Double): Boolean; static;
    class function SalvarFichaTransacao(CodEditar: Integer; Body: TJSONObject; Res: THorseResponse): Boolean; static;
  public
    class procedure Registrar;
    class procedure Listar(Req: THorseRequest; Res: THorseResponse);
    class procedure AlvosDisponiveis(Req: THorseRequest; Res: THorseResponse);
    class procedure ObterDetalhe(Req: THorseRequest; Res: THorseResponse);
    class procedure Criar(Req: THorseRequest; Res: THorseResponse);
    class procedure Atualizar(Req: THorseRequest; Res: THorseResponse);
    class procedure Excluir(Req: THorseRequest; Res: THorseResponse);
    class procedure RecalcularTodas(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  Data.DB,
  UnitConnection.Model.Interfaces,
  UnitDatabase,
  UnitProducao.Service;

{ TProducaoController }

class function TProducaoController.SuccessResponse(AData: TJSONValue; const AMessage: string): TJSONObject;
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

class function TProducaoController.ErrorResponse(const AMessage, ACode, ADetails: string): TJSONObject;
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

class function TProducaoController.ProximoGen(Conn: TFDConnection; Trans: TFDTransaction; const NomeGen: string): Integer;
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

class function TProducaoController.NormalizarTipoAlvo(const Tipo: string): string;
var
  T: string;
begin
  T := UpperCase(Trim(Tipo));
  if (T = 'OPCAO') or (T = 'OPCAO_NIVEL') or (T = 'SABOR') then
    Result := 'OPCAO'
  else if (T = 'ADICIONAL') or (T = 'COMPLEMENTO') then
    Result := 'ADICIONAL'
  else if T = 'PRODUTO' then
    Result := 'PRODUTO'
  else
    Result := '';
end;

class function TProducaoController.BuscarDadosAlvo(Conn: TFDConnection; Trans: TFDTransaction; const TipoAlvo: string; CodAlvo: Integer; out NomeAlvo: string; out PrecoVenda: Double): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  NomeAlvo := '';
  PrecoVenda := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    if TipoAlvo = 'PRODUTO' then
      Q.SQL.Text := 'SELECT PRO_NOME AS NOME, COALESCE(PRO_VALORV, 0) AS VALOR FROM PRODUTOS WHERE PRO_CODIGO = :COD'
    else if TipoAlvo = 'OPCAO' then
      Q.SQL.Text := 'SELECT OP_NOME AS NOME, COALESCE(OP_VALOR, 0) AS VALOR FROM OPCOES WHERE OP_CODIGO = :COD'
    else if TipoAlvo = 'ADICIONAL' then
      Q.SQL.Text := 'SELECT ADI_NOME AS NOME, COALESCE(ADI_VALOR, 0) AS VALOR FROM ADICIONAIS WHERE ADI_CODIGO = :COD'
    else
      Exit;

    Q.ParamByName('COD').AsInteger := CodAlvo;
    Q.Open;
    if not Q.IsEmpty then
    begin
      Result := True;
      NomeAlvo := Q.FieldByName('NOME').AsString;
      PrecoVenda := Q.FieldByName('VALOR').AsFloat;
    end;
  finally
    Q.DisposeOf;
  end;
end;

class procedure TProducaoController.Listar(Req: THorseRequest; Res: THorseResponse);
var
  Query: iQuery;
  Busca, TipoFiltro, TipoAlvo: string;
  Lista: TJSONArray;
  Item: TJSONObject;
  CustoUnit, PrecoVenda, Markup, PrecoSugerido, LucroUnit, MargemPerc: Double;
  AlertaMargem: Boolean;
begin
  TProducaoService.GarantirEstrutura;
  Query := TDatabase.Query;
  Lista := TJSONArray.Create;
  try
    Busca := '';
    if Req.Query.ContainsKey('busca') then
      Busca := UpperCase(Trim(Req.Query.Items['busca']));
    TipoFiltro := '';
    if Req.Query.ContainsKey('tipo_alvo') then
      TipoFiltro := NormalizarTipoAlvo(Req.Query.Items['tipo_alvo']);

    Query.Clear;
    Query.Add('SELECT');
    Query.Add('  F.FT_CODIGO, F.FT_TIPO_ALVO, F.FT_COD_ALVO, F.FT_NOME,');
    Query.Add('  COALESCE(F.FT_RENDIMENTO, 1) FT_RENDIMENTO, COALESCE(F.FT_UNIDADE_REND, ''UN'') FT_UNIDADE_REND,');
    Query.Add('  COALESCE(F.FT_PERDA_PERC, 0) FT_PERDA_PERC, COALESCE(F.FT_MARKUP_PERC, 0) FT_MARKUP_PERC,');
    Query.Add('  COALESCE(F.FT_CUSTO_INDIRETO, 0) FT_CUSTO_INDIRETO,');
    Query.Add('  COALESCE(F.FT_CUSTO_TOTAL, 0) FT_CUSTO_TOTAL, COALESCE(F.FT_CUSTO_UNIT, 0) FT_CUSTO_UNIT,');
    Query.Add('  COALESCE(F.FT_ATIVO, ''S'') FT_ATIVO, F.FT_DATA_ATUALIZACAO,');
    Query.Add('  CASE UPPER(TRIM(F.FT_TIPO_ALVO))');
    Query.Add('    WHEN ''PRODUTO'' THEN COALESCE(P.PRO_NOME, F.FT_NOME)');
    Query.Add('    WHEN ''OPCAO'' THEN COALESCE(O.OP_NOME, F.FT_NOME)');
    Query.Add('    WHEN ''ADICIONAL'' THEN COALESCE(A.ADI_NOME, F.FT_NOME)');
    Query.Add('    ELSE F.FT_NOME END AS ALVO_NOME,');
    Query.Add('  CASE UPPER(TRIM(F.FT_TIPO_ALVO))');
    Query.Add('    WHEN ''PRODUTO'' THEN COALESCE(P.PRO_VALORV, 0)');
    Query.Add('    WHEN ''OPCAO'' THEN COALESCE(O.OP_VALOR, 0)');
    Query.Add('    WHEN ''ADICIONAL'' THEN COALESCE(A.ADI_VALOR, 0)');
    Query.Add('    ELSE 0 END AS PRECO_VENDA,');
    Query.Add('  (SELECT COUNT(*) FROM FICHA_TECNICA_ITENS I WHERE I.FTI_FT = F.FT_CODIGO) AS QTD_ITENS');
    Query.Add('FROM FICHA_TECNICA F');
    Query.Add('LEFT JOIN PRODUTOS P ON UPPER(TRIM(F.FT_TIPO_ALVO)) = ''PRODUTO'' AND P.PRO_CODIGO = F.FT_COD_ALVO');
    Query.Add('LEFT JOIN OPCOES O ON UPPER(TRIM(F.FT_TIPO_ALVO)) = ''OPCAO'' AND O.OP_CODIGO = F.FT_COD_ALVO');
    Query.Add('LEFT JOIN ADICIONAIS A ON UPPER(TRIM(F.FT_TIPO_ALVO)) = ''ADICIONAL'' AND A.ADI_CODIGO = F.FT_COD_ALVO');
    Query.Add('WHERE 1 = 1');

    if not TipoFiltro.IsEmpty then
    begin
      Query.Add('  AND UPPER(TRIM(F.FT_TIPO_ALVO)) = :TIPO_ALVO');
      Query.AddParam('TIPO_ALVO', TipoFiltro);
    end;
    if not Busca.IsEmpty then
    begin
      Query.Add('  AND (UPPER(COALESCE(F.FT_NOME, '''')) LIKE :BUSCA OR UPPER(COALESCE(P.PRO_NOME, '''')) LIKE :BUSCA OR UPPER(COALESCE(O.OP_NOME, '''')) LIKE :BUSCA OR UPPER(COALESCE(A.ADI_NOME, '''')) LIKE :BUSCA)');
      Query.AddParam('BUSCA', '%' + Busca + '%');
    end;

    Query.Add('ORDER BY F.FT_TIPO_ALVO, F.FT_NOME, F.FT_CODIGO DESC');
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      TipoAlvo := UpperCase(Trim(Query.DataSet.FieldByName('FT_TIPO_ALVO').AsString));
      CustoUnit := Query.DataSet.FieldByName('FT_CUSTO_UNIT').AsFloat;
      PrecoVenda := Query.DataSet.FieldByName('PRECO_VENDA').AsFloat;
      Markup := Query.DataSet.FieldByName('FT_MARKUP_PERC').AsFloat;
      PrecoSugerido := RoundTo(CustoUnit * (1.0 + (Markup / 100.0)), -2);
      LucroUnit := RoundTo(PrecoVenda - CustoUnit, -4);
      if PrecoVenda > 0 then
        MargemPerc := RoundTo(((PrecoVenda - CustoUnit) / PrecoVenda) * 100.0, -2)
      else
        MargemPerc := 0;
      AlertaMargem := (PrecoVenda > 0) and ((CustoUnit >= PrecoVenda) or (MargemPerc < 20.0));

      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('FT_CODIGO').AsInteger));
      Item.AddPair('tipo_alvo', TipoAlvo);
      Item.AddPair('cod_alvo', TJSONNumber.Create(Query.DataSet.FieldByName('FT_COD_ALVO').AsInteger));
      Item.AddPair('nome', Query.DataSet.FieldByName('FT_NOME').AsString);
      Item.AddPair('alvo_nome', Query.DataSet.FieldByName('ALVO_NOME').AsString);
      Item.AddPair('rendimento', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FT_RENDIMENTO').AsFloat, -4)));
      Item.AddPair('unidade_rend', Query.DataSet.FieldByName('FT_UNIDADE_REND').AsString);
      Item.AddPair('perda_perc', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FT_PERDA_PERC').AsFloat, -2)));
      Item.AddPair('markup_perc', TJSONNumber.Create(RoundTo(Markup, -2)));
      Item.AddPair('custo_indireto', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FT_CUSTO_INDIRETO').AsFloat, -4)));
      Item.AddPair('custo_total', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FT_CUSTO_TOTAL').AsFloat, -4)));
      Item.AddPair('custo_unit', TJSONNumber.Create(RoundTo(CustoUnit, -4)));
      Item.AddPair('preco_venda', TJSONNumber.Create(RoundTo(PrecoVenda, -2)));
      Item.AddPair('preco_sugerido', TJSONNumber.Create(PrecoSugerido));
      Item.AddPair('lucro_unit', TJSONNumber.Create(LucroUnit));
      Item.AddPair('margem_perc', TJSONNumber.Create(MargemPerc));
      Item.AddPair('alerta_margem', TJSONBool.Create(AlertaMargem));
      Item.AddPair('qtd_ingredientes', TJSONNumber.Create(Query.DataSet.FieldByName('QTD_ITENS').AsInteger));
      Item.AddPair('ativo', TJSONBool.Create(Query.DataSet.FieldByName('FT_ATIVO').AsString = 'S'));
      if not Query.DataSet.FieldByName('FT_DATA_ATUALIZACAO').IsNull then
        Item.AddPair('data_atualizacao', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Query.DataSet.FieldByName('FT_DATA_ATUALIZACAO').AsDateTime))
      else
        Item.AddPair('data_atualizacao', '');

      Lista.AddElement(Item);
      Query.DataSet.Next;
    end;

    Res.Send<TJSONObject>(SuccessResponse(Lista, 'Fichas tecnicas carregadas.'));
    Lista := nil;
  finally
    if Assigned(Lista) then
      Lista.Free;
  end;
end;

class procedure TProducaoController.AlvosDisponiveis(Req: THorseRequest; Res: THorseResponse);
var
  Query: iQuery;
  DataObj, Obj: TJSONObject;
  ArrProd, ArrOpcoes, ArrAdic, ArrInsumos: TJSONArray;
  TipoNorm: string;
begin
  TProducaoService.GarantirEstrutura;
  Query := TDatabase.Query;
  DataObj := TJSONObject.Create;
  ArrProd := TJSONArray.Create;
  ArrOpcoes := TJSONArray.Create;
  ArrAdic := TJSONArray.Create;
  ArrInsumos := TJSONArray.Create;
  try
    // 1) Produtos de PRODUCAO
    Query.Clear;
    Query.Add('SELECT P.PRO_CODIGO, P.PRO_NOME, COALESCE(P.PRO_VALORV, 0) PRO_VALORV,');
    Query.Add('       COALESCE(P.PRO_EMBALAGEM, ''UN'') PRO_EMBALAGEM,');
    Query.Add('       COALESCE(F.FT_CODIGO, 0) FT_CODIGO');
    Query.Add('FROM PRODUTOS P');
    Query.Add('LEFT JOIN FICHA_TECNICA F ON F.FT_TIPO_ALVO = ''PRODUTO'' AND F.FT_COD_ALVO = P.PRO_CODIGO AND COALESCE(F.FT_ATIVO, ''S'') = ''S''');
    Query.Add('WHERE COALESCE(P.PRO_ESTADO, ''ATIVO'') = ''ATIVO''');
    Query.Add('  AND UPPER(TRIM(COALESCE(P.PRO_TIPO, ''''))) IN (''PRODUCAO'', ''PRODUÇÃO'', ''PROD'')');
    Query.Add('ORDER BY P.PRO_NOME');
    Query.Open;
    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
      Obj.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
      Obj.AddPair('contexto', 'Produto de Producao');
      Obj.AddPair('valor', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('PRO_VALORV').AsFloat, -2)));
      Obj.AddPair('unidade', TProducaoService.NormalizarUnidade(Query.DataSet.FieldByName('PRO_EMBALAGEM').AsString));
      Obj.AddPair('ficha_codigo', TJSONNumber.Create(Query.DataSet.FieldByName('FT_CODIGO').AsInteger));
      ArrProd.AddElement(Obj);
      Query.DataSet.Next;
    end;

    // 2) Opcoes de Niveis (Sabores)
    Query.Clear;
    Query.Add('SELECT O.OP_CODIGO, O.OP_NOME, COALESCE(O.OP_VALOR, 0) OP_VALOR,');
    Query.Add('       COALESCE(N.NI_TITULO, '''') NI_TITULO, COALESCE(P.PRO_NOME, '''') PRO_NOME,');
    Query.Add('       COALESCE(F.FT_CODIGO, 0) FT_CODIGO');
    Query.Add('FROM OPCOES O');
    Query.Add('LEFT JOIN NIVEIS N ON N.NI_CODIGO = O.OP_NI');
    Query.Add('LEFT JOIN PRODUTOS P ON P.PRO_CODIGO = N.NI_PRO');
    Query.Add('LEFT JOIN FICHA_TECNICA F ON F.FT_TIPO_ALVO = ''OPCAO'' AND F.FT_COD_ALVO = O.OP_CODIGO AND COALESCE(F.FT_ATIVO, ''S'') = ''S''');
    Query.Add('WHERE COALESCE(O.OP_ATIVO, ''S'') = ''S''');
    Query.Add('ORDER BY P.PRO_NOME, N.NI_TITULO, O.OP_NOME');
    Query.Open;
    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('OP_CODIGO').AsInteger));
      Obj.AddPair('nome', Query.DataSet.FieldByName('OP_NOME').AsString);
      Obj.AddPair('contexto', Trim(Query.DataSet.FieldByName('PRO_NOME').AsString + ' > ' + Query.DataSet.FieldByName('NI_TITULO').AsString));
      Obj.AddPair('valor', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('OP_VALOR').AsFloat, -2)));
      Obj.AddPair('unidade', 'UN');
      Obj.AddPair('ficha_codigo', TJSONNumber.Create(Query.DataSet.FieldByName('FT_CODIGO').AsInteger));
      ArrOpcoes.AddElement(Obj);
      Query.DataSet.Next;
    end;

    // 3) Adicionais / Complementos
    Query.Clear;
    Query.Add('SELECT A.ADI_CODIGO, A.ADI_NOME, COALESCE(A.ADI_VALOR, 0) ADI_VALOR,');
    Query.Add('       COALESCE(F.FT_CODIGO, 0) FT_CODIGO');
    Query.Add('FROM ADICIONAIS A');
    Query.Add('LEFT JOIN FICHA_TECNICA F ON F.FT_TIPO_ALVO = ''ADICIONAL'' AND F.FT_COD_ALVO = A.ADI_CODIGO AND COALESCE(F.FT_ATIVO, ''S'') = ''S''');
    Query.Add('WHERE COALESCE(A.ADI_ESTADO, ''ATIVO'') <> ''INATIVO''');
    Query.Add('ORDER BY A.ADI_NOME');
    Query.Open;
    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('ADI_CODIGO').AsInteger));
      Obj.AddPair('nome', Query.DataSet.FieldByName('ADI_NOME').AsString);
      Obj.AddPair('contexto', 'Adicional / Complemento');
      Obj.AddPair('valor', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('ADI_VALOR').AsFloat, -2)));
      Obj.AddPair('unidade', 'UN');
      Obj.AddPair('ficha_codigo', TJSONNumber.Create(Query.DataSet.FieldByName('FT_CODIGO').AsInteger));
      ArrAdic.AddElement(Obj);
      Query.DataSet.Next;
    end;

    // 4) Insumos disponiveis (MP + PRODUCAO para sub-receitas)
    Query.Clear;
    Query.Add('SELECT P.PRO_CODIGO, P.PRO_NOME, COALESCE(P.PRO_TIPO, '''') PRO_TIPO,');
    Query.Add('       COALESCE(P.PRO_EMBALAGEM, ''UN'') PRO_EMBALAGEM,');
    Query.Add('       COALESCE(P.PRO_VALORC, 0) PRO_VALORC, COALESCE(P.PRO_VALORCM, 0) PRO_VALORCM,');
    Query.Add('       COALESCE(P.PRO_QUANTIDADE, 0) PRO_QUANTIDADE');
    Query.Add('FROM PRODUTOS P');
    Query.Add('WHERE COALESCE(P.PRO_ESTADO, ''ATIVO'') <> ''INATIVO''');
    Query.Add('  AND UPPER(TRIM(COALESCE(P.PRO_TIPO, ''REVENDA''))) IN (''MP'', ''MATERIA_PRIMA'', ''MATERIA-PRIMA'', ''PRODUCAO'', ''PRODUÇÃO'', ''PROD'')');
    Query.Add('ORDER BY P.PRO_NOME');
    Query.Open;
    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      TipoNorm := TProducaoService.NormalizarTipoProduto(Query.DataSet.FieldByName('PRO_TIPO').AsString);
      Obj := TJSONObject.Create;
      Obj.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
      Obj.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
      Obj.AddPair('tipo', TipoNorm);
      Obj.AddPair('unidade', TProducaoService.NormalizarUnidade(Query.DataSet.FieldByName('PRO_EMBALAGEM').AsString));
      Obj.AddPair('valorc', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('PRO_VALORC').AsFloat, -4)));
      Obj.AddPair('valorcm', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('PRO_VALORCM').AsFloat, -4)));
      Obj.AddPair('quantidade', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('PRO_QUANTIDADE').AsFloat, -2)));
      ArrInsumos.AddElement(Obj);
      Query.DataSet.Next;
    end;

    DataObj.AddPair('produtos_producao', ArrProd); ArrProd := nil;
    DataObj.AddPair('opcoes_niveis', ArrOpcoes); ArrOpcoes := nil;
    DataObj.AddPair('adicionais', ArrAdic); ArrAdic := nil;
    DataObj.AddPair('insumos', ArrInsumos); ArrInsumos := nil;

    Res.Send<TJSONObject>(SuccessResponse(DataObj, 'Alvos e insumos carregados.'));
    DataObj := nil;
  finally
    if Assigned(ArrProd) then ArrProd.Free;
    if Assigned(ArrOpcoes) then ArrOpcoes.Free;
    if Assigned(ArrAdic) then ArrAdic.Free;
    if Assigned(ArrInsumos) then ArrInsumos.Free;
    if Assigned(DataObj) then DataObj.Free;
  end;
end;

class procedure TProducaoController.ObterDetalhe(Req: THorseRequest; Res: THorseResponse);
var
  Codigo, CodAlvo: Integer;
  Query: iQuery;
  DataObj, ItemObj: TJSONObject;
  ItensArr: TJSONArray;
  TipoAlvo, AlvoNome, PrecoStr: string;
  CustoUnit, PrecoVenda, Markup: Double;
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Transacao: TFDTransaction;
begin
  TProducaoService.GarantirEstrutura;
  if not TryStrToInt(Req.Params.Items['codigo'], Codigo) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Codigo de ficha invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Query := TDatabase.Query;
  Query.Clear;
  Query.Add('SELECT * FROM FICHA_TECNICA WHERE FT_CODIGO = :COD');
  Query.AddParam('COD', Codigo);
  Query.Open;

  if Query.DataSet.IsEmpty then
  begin
    Res.Status(THTTPStatus.NotFound)
      .Send<TJSONObject>(ErrorResponse('Ficha tecnica nao encontrada.', 'NOT_FOUND'));
    Exit;
  end;

  TipoAlvo := UpperCase(Trim(Query.DataSet.FieldByName('FT_TIPO_ALVO').AsString));
  CodAlvo := Query.DataSet.FieldByName('FT_COD_ALVO').AsInteger;
  CustoUnit := Query.DataSet.FieldByName('FT_CUSTO_UNIT').AsFloat;
  Markup := Query.DataSet.FieldByName('FT_MARKUP_PERC').AsFloat;

  PrecoVenda := 0;
  AlvoNome := Query.DataSet.FieldByName('FT_NOME').AsString;
  BancoDados := TDatabase.Connection;
  IndiceConexao := BancoDados.Connected;
  Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
  Transacao := TFDTransaction.Create(nil);
  try
    Transacao.Connection := Conexao;
    Transacao.StartTransaction;
    BuscarDadosAlvo(Conexao, Transacao, TipoAlvo, CodAlvo, PrecoStr, PrecoVenda);
    if not PrecoStr.IsEmpty then
      AlvoNome := PrecoStr;
    Transacao.Commit;
  finally
    Transacao.DisposeOf;
    BancoDados.Disconnected(IndiceConexao);
  end;

  DataObj := TJSONObject.Create;
  DataObj.AddPair('codigo', TJSONNumber.Create(Codigo));
  DataObj.AddPair('tipo_alvo', TipoAlvo);
  DataObj.AddPair('cod_alvo', TJSONNumber.Create(CodAlvo));
  DataObj.AddPair('nome', Query.DataSet.FieldByName('FT_NOME').AsString);
  DataObj.AddPair('alvo_nome', AlvoNome);
  DataObj.AddPair('rendimento', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FT_RENDIMENTO').AsFloat, -4)));
  DataObj.AddPair('unidade_rend', Query.DataSet.FieldByName('FT_UNIDADE_REND').AsString);
  DataObj.AddPair('perda_perc', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FT_PERDA_PERC').AsFloat, -2)));
  DataObj.AddPair('markup_perc', TJSONNumber.Create(RoundTo(Markup, -2)));
  DataObj.AddPair('custo_indireto', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FT_CUSTO_INDIRETO').AsFloat, -4)));
  DataObj.AddPair('modo_preparo', Query.DataSet.FieldByName('FT_MODO_PREPARO').AsString);
  DataObj.AddPair('custo_total', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FT_CUSTO_TOTAL').AsFloat, -4)));
  DataObj.AddPair('custo_unit', TJSONNumber.Create(RoundTo(CustoUnit, -4)));
  DataObj.AddPair('preco_venda', TJSONNumber.Create(RoundTo(PrecoVenda, -2)));
  DataObj.AddPair('preco_sugerido', TJSONNumber.Create(RoundTo(CustoUnit * (1.0 + (Markup / 100.0)), -2)));
  DataObj.AddPair('lucro_unit', TJSONNumber.Create(RoundTo(PrecoVenda - CustoUnit, -4)));
  if PrecoVenda > 0 then
    DataObj.AddPair('margem_perc', TJSONNumber.Create(RoundTo(((PrecoVenda - CustoUnit) / PrecoVenda) * 100.0, -2)))
  else
    DataObj.AddPair('margem_perc', TJSONNumber.Create(0));
  DataObj.AddPair('ativo', TJSONBool.Create(Query.DataSet.FieldByName('FT_ATIVO').AsString = 'S'));

  ItensArr := TJSONArray.Create;
  Query.Clear;
  Query.Add('SELECT I.FTI_CODIGO, I.FTI_PRO_INSUMO, I.FTI_QUANTIDADE, I.FTI_UNIDADE,');
  Query.Add('       I.FTI_FATOR_BASE, I.FTI_CUSTO_UNIT_SNAP, I.FTI_CUSTO_TOTAL, I.FTI_PERCENTUAL,');
  Query.Add('       P.PRO_NOME, COALESCE(P.PRO_TIPO, '''') PRO_TIPO, COALESCE(P.PRO_EMBALAGEM, ''UN'') PRO_EMBALAGEM,');
  Query.Add('       COALESCE(NULLIF(P.PRO_VALORCM, 0), P.PRO_VALORC, 0) AS CUSTO_ATUAL');
  Query.Add('FROM FICHA_TECNICA_ITENS I');
  Query.Add('JOIN PRODUTOS P ON P.PRO_CODIGO = I.FTI_PRO_INSUMO');
  Query.Add('WHERE I.FTI_FT = :FT');
  Query.Add('ORDER BY I.FTI_CODIGO');
  Query.AddParam('FT', Codigo);
  Query.Open;

  Query.DataSet.First;
  while not Query.DataSet.Eof do
  begin
    ItemObj := TJSONObject.Create;
    ItemObj.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('FTI_CODIGO').AsInteger));
    ItemObj.AddPair('pro_insumo', TJSONNumber.Create(Query.DataSet.FieldByName('FTI_PRO_INSUMO').AsInteger));
    ItemObj.AddPair('insumo_nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
    ItemObj.AddPair('insumo_tipo', TProducaoService.NormalizarTipoProduto(Query.DataSet.FieldByName('PRO_TIPO').AsString));
    ItemObj.AddPair('insumo_unidade', TProducaoService.NormalizarUnidade(Query.DataSet.FieldByName('PRO_EMBALAGEM').AsString));
    ItemObj.AddPair('quantidade', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FTI_QUANTIDADE').AsFloat, -4)));
    ItemObj.AddPair('unidade', Query.DataSet.FieldByName('FTI_UNIDADE').AsString);
    ItemObj.AddPair('fator_base', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FTI_FATOR_BASE').AsFloat, -6)));
    ItemObj.AddPair('custo_unit_insumo', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('CUSTO_ATUAL').AsFloat, -4)));
    ItemObj.AddPair('custo_total', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FTI_CUSTO_TOTAL').AsFloat, -4)));
    ItemObj.AddPair('percentual', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('FTI_PERCENTUAL').AsFloat, -2)));
    ItensArr.AddElement(ItemObj);
    Query.DataSet.Next;
  end;

  DataObj.AddPair('itens', ItensArr);
  Res.Send<TJSONObject>(SuccessResponse(DataObj, 'Ficha tecnica carregada.'));
end;

class function TProducaoController.SalvarFichaTransacao(CodEditar: Integer; Body: TJSONObject; Res: THorseResponse): Boolean;
var
  TipoAlvo, Nome, UnidadeRend, ModoPreparo, NomeAlvo, UnidItem, UnidBaseInsumo: string;
  CodAlvo, CodFT, I, ProInsumo: Integer;
  Rendimento, PerdaPerc, MarkupPerc, CustoIndireto, PrecoVenda, QtdItem, FatorBase: Double;
  Ativo: Boolean;
  ItensArr: TJSONArray;
  RecalculadasArr: TJSONArray;
  ItemObj, RespObj: TJSONObject;
  InsumosArr: TArray<Integer>;
  InsumosList: TList<Integer>;
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Transacao: TFDTransaction;
  Q: TFDQuery;
  CustoAnt, CustoNov: Double;
  OutTipo, OutNome: string;
  OutCodAlvo: Integer;
begin
  Result := False;
  TipoAlvo := 'PRODUTO';
  if Body.TryGetValue<string>('tipo_alvo', TipoAlvo) then
    TipoAlvo := NormalizarTipoAlvo(TipoAlvo);
  if TipoAlvo.IsEmpty then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Tipo de alvo invalido (use PRODUTO, OPCAO ou ADICIONAL).', 'VALIDATION_ERROR'));
    Exit;
  end;

  CodAlvo := 0;
  Body.TryGetValue<Integer>('cod_alvo', CodAlvo);
  if CodAlvo <= 0 then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Selecione o produto, sabor ou adicional desta ficha tecnica.', 'VALIDATION_ERROR'));
    Exit;
  end;

  Nome := ''; Body.TryGetValue<string>('nome', Nome);
  Rendimento := 1; Body.TryGetValue<Double>('rendimento', Rendimento);
  if Rendimento <= 0 then Rendimento := 1;
  UnidadeRend := 'UN';
  if Body.TryGetValue<string>('unidade_rend', UnidadeRend) then
    UnidadeRend := TProducaoService.NormalizarUnidade(UnidadeRend);
  PerdaPerc := 0; Body.TryGetValue<Double>('perda_perc', PerdaPerc);
  if PerdaPerc < 0 then PerdaPerc := 0 else if PerdaPerc > 95 then PerdaPerc := 95;
  MarkupPerc := 100; Body.TryGetValue<Double>('markup_perc', MarkupPerc);
  if MarkupPerc < 0 then MarkupPerc := 0;
  CustoIndireto := 0; Body.TryGetValue<Double>('custo_indireto', CustoIndireto);
  if CustoIndireto < 0 then CustoIndireto := 0;
  ModoPreparo := ''; Body.TryGetValue<string>('modo_preparo', ModoPreparo);
  Ativo := True; Body.TryGetValue<Boolean>('ativo', Ativo);

  if (not Body.TryGetValue<TJSONArray>('itens', ItensArr)) or (ItensArr.Count = 0) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Adicione ao menos um ingrediente na ficha tecnica.', 'VALIDATION_ERROR'));
    Exit;
  end;

  InsumosList := TList<Integer>.Create;
  BancoDados := TDatabase.Connection;
  IndiceConexao := BancoDados.Connected;
  Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
  Transacao := TFDTransaction.Create(nil);
  try
    Transacao.Connection := Conexao;
    Transacao.Options.Params.Clear;
    Transacao.Options.Params.Add('write');
    Transacao.Options.Params.Add('read_committed');
    Transacao.Options.Params.Add('rec_version');
    Transacao.Options.Params.Add('nowait');

    Transacao.StartTransaction;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conexao;
        Q.Transaction := Transacao;

        if not BuscarDadosAlvo(Conexao, Transacao, TipoAlvo, CodAlvo, NomeAlvo, PrecoVenda) then
        begin
          Transacao.Rollback;
          Res.Status(THTTPStatus.NotFound)
            .Send<TJSONObject>(ErrorResponse('Alvo da ficha tecnica nao encontrado.', 'NOT_FOUND'));
          Exit;
        end;

        if Trim(Nome).IsEmpty then
          Nome := NomeAlvo;

        // Verifica ficha duplicada para o mesmo alvo
        Q.SQL.Text :=
          'SELECT FIRST 1 FT_CODIGO FROM FICHA_TECNICA ' +
          'WHERE UPPER(TRIM(FT_TIPO_ALVO)) = :TIPO AND FT_COD_ALVO = :ALVO AND FT_CODIGO <> :COD';
        Q.ParamByName('TIPO').AsString := TipoAlvo;
        Q.ParamByName('ALVO').AsInteger := CodAlvo;
        Q.ParamByName('COD').AsInteger := CodEditar;
        Q.Open;
        if not Q.IsEmpty then
        begin
          Transacao.Rollback;
          Res.Status(THTTPStatus.Conflict)
            .Send<TJSONObject>(ErrorResponse('Ja existe uma ficha tecnica para "' + NomeAlvo + '".', 'DUPLICATE_FICHA'));
          Exit;
        end;

        // Coleta insumos para checagem anti-ciclo
        for I := 0 to ItensArr.Count - 1 do
        begin
          if ItensArr.Items[I] is TJSONObject then
          begin
            ProInsumo := 0;
            TJSONObject(ItensArr.Items[I]).TryGetValue<Integer>('pro_insumo', ProInsumo);
            if ProInsumo > 0 then
              InsumosList.Add(ProInsumo);
          end;
        end;
        InsumosArr := InsumosList.ToArray;

        if (TipoAlvo = 'PRODUTO') and TProducaoService.VerificarCiclo(Conexao, Transacao, CodAlvo, InsumosArr) then
        begin
          Transacao.Rollback;
          Res.Status(422).Send<TJSONObject>(
            ErrorResponse('Referencia circular detectada: uma sub-receita nao pode usar ela mesma como ingrediente.', 'CIRCULAR_RECIPE')
          );
          Exit;
        end;

        if CodEditar > 0 then
        begin
          CodFT := CodEditar;
          Q.Close;
          Q.SQL.Text :=
            'UPDATE FICHA_TECNICA SET ' +
            '  FT_TIPO_ALVO = :TIPO, FT_COD_ALVO = :ALVO, FT_NOME = :NOME, ' +
            '  FT_RENDIMENTO = :REND, FT_UNIDADE_REND = :UNID, FT_PERDA_PERC = :PERDA, ' +
            '  FT_MARKUP_PERC = :MARKUP, FT_CUSTO_INDIRETO = :IND, FT_MODO_PREPARO = :PREP, ' +
            '  FT_ATIVO = :ATIVO, FT_DATA_ATUALIZACAO = CURRENT_TIMESTAMP ' +
            'WHERE FT_CODIGO = :COD';
          Q.ParamByName('COD').AsInteger := CodFT;
        end
        else
        begin
          CodFT := ProximoGen(Conexao, Transacao, 'GEN_FT');
          Q.Close;
          Q.SQL.Text :=
            'INSERT INTO FICHA_TECNICA (' +
            '  FT_CODIGO, FT_TIPO_ALVO, FT_COD_ALVO, FT_NOME, FT_RENDIMENTO, FT_UNIDADE_REND, ' +
            '  FT_PERDA_PERC, FT_MARKUP_PERC, FT_CUSTO_INDIRETO, FT_MODO_PREPARO, ' +
            '  FT_CUSTO_TOTAL, FT_CUSTO_UNIT, FT_ATIVO, FT_DATA_ATUALIZACAO' +
            ') VALUES (' +
            '  :COD, :TIPO, :ALVO, :NOME, :REND, :UNID, ' +
            '  :PERDA, :MARKUP, :IND, :PREP, ' +
            '  0, 0, :ATIVO, CURRENT_TIMESTAMP' +
            ')';
          Q.ParamByName('COD').AsInteger := CodFT;
        end;

        Q.ParamByName('TIPO').AsString := TipoAlvo;
        Q.ParamByName('ALVO').AsInteger := CodAlvo;
        Q.ParamByName('NOME').AsString := Copy(Trim(Nome), 1, 120);
        Q.ParamByName('REND').AsFloat := Rendimento;
        Q.ParamByName('UNID').AsString := Copy(UnidadeRend, 1, 10);
        Q.ParamByName('PERDA').AsFloat := PerdaPerc;
        Q.ParamByName('MARKUP').AsFloat := MarkupPerc;
        Q.ParamByName('IND').AsFloat := CustoIndireto;
        Q.ParamByName('PREP').AsString := Copy(Trim(ModoPreparo), 1, 2000);
        Q.ParamByName('ATIVO').AsString := IfThen(Ativo, 'S', 'N');
        Q.ExecSQL;

        // Regrava itens
        Q.Close;
        Q.SQL.Text := 'DELETE FROM FICHA_TECNICA_ITENS WHERE FTI_FT = :FT';
        Q.ParamByName('FT').AsInteger := CodFT;
        Q.ExecSQL;

        for I := 0 to ItensArr.Count - 1 do
        begin
          if not (ItensArr.Items[I] is TJSONObject) then
            Continue;
          ItemObj := TJSONObject(ItensArr.Items[I]);
          ProInsumo := 0; ItemObj.TryGetValue<Integer>('pro_insumo', ProInsumo);
          if ProInsumo <= 0 then
            Continue;

          QtdItem := 0; ItemObj.TryGetValue<Double>('quantidade', QtdItem);
          if QtdItem <= 0 then
            Continue;

          UnidItem := 'UN';
          if ItemObj.TryGetValue<string>('unidade', UnidItem) then
            UnidItem := TProducaoService.NormalizarUnidade(UnidItem);

          FatorBase := 0; ItemObj.TryGetValue<Double>('fator_base', FatorBase);
          if FatorBase <= 0 then
          begin
            Q.Close;
            Q.SQL.Text := 'SELECT COALESCE(PRO_EMBALAGEM, ''UN'') EMB FROM PRODUTOS WHERE PRO_CODIGO = :PRO';
            Q.ParamByName('PRO').AsInteger := ProInsumo;
            Q.Open;
            UnidBaseInsumo := '';
            if not Q.IsEmpty then
              UnidBaseInsumo := Q.FieldByName('EMB').AsString;
            FatorBase := TProducaoService.CalcularFatorConversao(UnidItem, UnidBaseInsumo);
          end;

          Q.Close;
          Q.SQL.Text :=
            'INSERT INTO FICHA_TECNICA_ITENS (' +
            '  FTI_CODIGO, FTI_FT, FTI_PRO_INSUMO, FTI_QUANTIDADE, FTI_UNIDADE, ' +
            '  FTI_FATOR_BASE, FTI_CUSTO_UNIT_SNAP, FTI_CUSTO_TOTAL, FTI_PERCENTUAL' +
            ') VALUES (' +
            '  :CODIGO, :FT, :PRO, :QTD, :UNID, :FATOR, 0, 0, 0' +
            ')';
          Q.ParamByName('CODIGO').AsInteger := ProximoGen(Conexao, Transacao, 'GEN_FTI');
          Q.ParamByName('FT').AsInteger := CodFT;
          Q.ParamByName('PRO').AsInteger := ProInsumo;
          Q.ParamByName('QTD').AsFloat := QtdItem;
          Q.ParamByName('UNID').AsString := Copy(UnidItem, 1, 10);
          Q.ParamByName('FATOR').AsFloat := FatorBase;
          Q.ExecSQL;
        end;

        // Recalcula esta ficha e propaga em cascata se for PRODUTO
        TProducaoService.RecalcularFicha(Conexao, Transacao, CodFT, CustoAnt, CustoNov, OutTipo, OutCodAlvo, OutNome);
        RecalculadasArr := TJSONArray.Create;
        try
          if TipoAlvo = 'PRODUTO' then
            TProducaoService.RecalcularEmCascata(Conexao, Transacao, CodAlvo, RecalculadasArr);

          Transacao.Commit;

          RespObj := TJSONObject.Create;
          RespObj.AddPair('codigo', TJSONNumber.Create(CodFT));
          RespObj.AddPair('tipo_alvo', TipoAlvo);
          RespObj.AddPair('cod_alvo', TJSONNumber.Create(CodAlvo));
          RespObj.AddPair('nome', Nome);
          RespObj.AddPair('custo_unit', TJSONNumber.Create(RoundTo(CustoNov, -4)));
          RespObj.AddPair('preco_venda', TJSONNumber.Create(RoundTo(PrecoVenda, -2)));
          RespObj.AddPair('preco_sugerido', TJSONNumber.Create(RoundTo(CustoNov * (1.0 + (MarkupPerc / 100.0)), -2)));
          RespObj.AddPair('fichas_recalculadas', RecalculadasArr);
          RecalculadasArr := nil;

          Res.Status(IfThen(CodEditar > 0, Integer(THTTPStatus.OK), Integer(THTTPStatus.Created)))
            .Send<TJSONObject>(SuccessResponse(RespObj, 'Ficha tecnica salva com sucesso.'));
          Result := True;
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
  finally
    Transacao.DisposeOf;
    BancoDados.Disconnected(IndiceConexao);
    InsumosList.Free;
  end;
end;

class procedure TProducaoController.Criar(Req: THorseRequest; Res: THorseResponse);
var
  Body: TJSONObject;
begin
  TProducaoService.GarantirEstrutura;
  Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
  if not Assigned(Body) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Corpo da requisicao invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;
  try
    try
      SalvarFichaTransacao(0, Body, Res);
    except
      on E: Exception do
        Res.Status(THTTPStatus.InternalServerError)
          .Send<TJSONObject>(ErrorResponse('Falha ao criar ficha tecnica.', 'INTERNAL_ERROR', E.Message));
    end;
  finally
    Body.Free;
  end;
end;

class procedure TProducaoController.Atualizar(Req: THorseRequest; Res: THorseResponse);
var
  Body: TJSONObject;
  Codigo: Integer;
begin
  TProducaoService.GarantirEstrutura;
  if not TryStrToInt(Req.Params.Items['codigo'], Codigo) or (Codigo <= 0) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Codigo de ficha invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;
  Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
  if not Assigned(Body) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Corpo da requisicao invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;
  try
    try
      SalvarFichaTransacao(Codigo, Body, Res);
    except
      on E: Exception do
        Res.Status(THTTPStatus.InternalServerError)
          .Send<TJSONObject>(ErrorResponse('Falha ao atualizar ficha tecnica.', 'INTERNAL_ERROR', E.Message));
    end;
  finally
    Body.Free;
  end;
end;

class procedure TProducaoController.Excluir(Req: THorseRequest; Res: THorseResponse);
var
  Codigo: Integer;
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Transacao: TFDTransaction;
  Q: TFDQuery;
begin
  TProducaoService.GarantirEstrutura;
  if not TryStrToInt(Req.Params.Items['codigo'], Codigo) or (Codigo <= 0) then
  begin
    Res.Status(THTTPStatus.BadRequest)
      .Send<TJSONObject>(ErrorResponse('Codigo de ficha invalido.', 'VALIDATION_ERROR'));
    Exit;
  end;

  BancoDados := TDatabase.Connection;
  IndiceConexao := BancoDados.Connected;
  Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
  Transacao := TFDTransaction.Create(nil);
  try
    Transacao.Connection := Conexao;
    Transacao.StartTransaction;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conexao;
        Q.Transaction := Transacao;
        Q.SQL.Text := 'DELETE FROM FICHA_TECNICA_ITENS WHERE FTI_FT = :COD';
        Q.ParamByName('COD').AsInteger := Codigo;
        Q.ExecSQL;

        Q.Close;
        Q.SQL.Text := 'DELETE FROM FICHA_TECNICA WHERE FT_CODIGO = :COD';
        Q.ParamByName('COD').AsInteger := Codigo;
        Q.ExecSQL;
      finally
        Q.DisposeOf;
      end;
      Transacao.Commit;
      Res.Send<TJSONObject>(SuccessResponse(nil, 'Ficha tecnica excluida.'));
    except
      on E: Exception do
      begin
        if Transacao.Active then Transacao.Rollback;
        Res.Status(THTTPStatus.InternalServerError)
          .Send<TJSONObject>(ErrorResponse('Falha ao excluir ficha tecnica.', 'INTERNAL_ERROR', E.Message));
      end;
    end;
  finally
    Transacao.DisposeOf;
    BancoDados.Disconnected(IndiceConexao);
  end;
end;

class procedure TProducaoController.RecalcularTodas(Req: THorseRequest; Res: THorseResponse);
var
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Transacao: TFDTransaction;
  Q: TFDQuery;
  Passagem, CodFT, CodAlvo, TotalAtualizadas: Integer;
  CustoAnt, CustoNov: Double;
  TipoAlvo, NomeAlvo: string;
  Codigos: TList<Integer>;
  RespObj: TJSONObject;
begin
  TProducaoService.GarantirEstrutura;
  BancoDados := TDatabase.Connection;
  IndiceConexao := BancoDados.Connected;
  Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
  Transacao := TFDTransaction.Create(nil);
  Codigos := TList<Integer>.Create;
  try
    Transacao.Connection := Conexao;
    Transacao.StartTransaction;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conexao;
        Q.Transaction := Transacao;
        Q.SQL.Text := 'SELECT FT_CODIGO FROM FICHA_TECNICA WHERE COALESCE(FT_ATIVO, ''S'') = ''S'' ORDER BY FT_CODIGO';
        Q.Open;
        while not Q.Eof do
        begin
          Codigos.Add(Q.FieldByName('FT_CODIGO').AsInteger);
          Q.Next;
        end;
      finally
        Q.DisposeOf;
      end;

      // ATE 5 passagens garantem convergencia para sub-receitas em multiplos niveis
      for Passagem := 1 to 5 do
      begin
        for CodFT in Codigos do
          TProducaoService.RecalcularFicha(Conexao, Transacao, CodFT, CustoAnt, CustoNov, TipoAlvo, CodAlvo, NomeAlvo);
      end;

      TotalAtualizadas := Codigos.Count;
      Transacao.Commit;

      RespObj := TJSONObject.Create;
      RespObj.AddPair('recalculadas', TJSONNumber.Create(TotalAtualizadas));
      Res.Send<TJSONObject>(SuccessResponse(RespObj, 'Todas as fichas tecnicas foram recalculadas.'));
    except
      on E: Exception do
      begin
        if Transacao.Active then Transacao.Rollback;
        Res.Status(THTTPStatus.InternalServerError)
          .Send<TJSONObject>(ErrorResponse('Falha ao recalcular fichas tecnicas.', 'INTERNAL_ERROR', E.Message));
      end;
    end;
  finally
    Codigos.Free;
    Transacao.DisposeOf;
    BancoDados.Disconnected(IndiceConexao);
  end;
end;

class procedure TProducaoController.Registrar;
begin
  THorse.Get('/v1/fichas-tecnicas', Listar);
  THorse.Get('/v1/fichas-tecnicas/alvos-disponiveis', AlvosDisponiveis);
  THorse.Post('/v1/fichas-tecnicas/recalcular-todas', RecalcularTodas);
  THorse.Get('/v1/fichas-tecnicas/:codigo', ObterDetalhe);
  THorse.Post('/v1/fichas-tecnicas', Criar);
  THorse.Put('/v1/fichas-tecnicas/:codigo', Atualizar);
  THorse.Delete('/v1/fichas-tecnicas/:codigo', Excluir);
end;

end.
