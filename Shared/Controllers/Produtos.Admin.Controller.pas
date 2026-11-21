unit Produtos.Admin.Controller;

interface

uses
  Horse,
  Horse.Commons,
  System.JSON;

type
  TProdutosAdminController = class
  private
    class function SuccessResponse(AData: TJSONValue; const AMessage: string = ''): TJSONObject; static;
    class function ObterGrupoPadrao: Integer; static;
    class function ObterCodigoUnidadeMed(const AUnidade: string): Integer; static;
  public
    class procedure Registrar;
    class procedure ListarAdmin(Req: THorseRequest; Res: THorseResponse);
    class procedure ListarContas(Req: THorseRequest; Res: THorseResponse);
    class procedure ListarUnidades(Req: THorseRequest; Res: THorseResponse);
    class procedure PostProduto(Req: THorseRequest; Res: THorseResponse);
    class procedure PutProduto(Req: THorseRequest; Res: THorseResponse);
    class procedure DeleteProduto(Req: THorseRequest; Res: THorseResponse);
    class procedure GetImagemProduto(Req: THorseRequest; Res: THorseResponse);
    class procedure GetImagemCategoria(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  UnitDatabase,
  UnitConnection.Model.Interfaces,
  UnitFunctions,
  UnitProdutos.Model,
  UnitTabela.Helpers,
  UnitProducao.Service;

class function TProdutosAdminController.SuccessResponse(AData: TJSONValue; const AMessage: string): TJSONObject;
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

class function TProdutosAdminController.ObterGrupoPadrao: Integer;
var
  Q: iQuery;
begin
  Result := 0;
  Q := TDatabase.Query;
  Q.Clear;
  Q.Add('SELECT FIRST 1 GRU_CODIGO FROM GRUPOS ORDER BY GRU_CODIGO');
  Q.Open;
  if not Q.DataSet.IsEmpty then
    Result := Q.DataSet.FieldByName('GRU_CODIGO').AsInteger;
end;

class function TProdutosAdminController.ObterCodigoUnidadeMed(const AUnidade: string): Integer;
var
  Q: iQuery;
  Unid: string;
begin
  Result := 0;
  Unid := Copy(TProducaoService.NormalizarUnidade(AUnidade), 1, 3);
  if Unid.IsEmpty then
    Exit;
  Q := TDatabase.Query;
  Q.Clear;
  Q.Add('SELECT FIRST 1 UM_CODIGO FROM UNIDADE_MED WHERE UPPER(TRIM(UM_UNIDADE)) = :UNID');
  Q.AddParam('UNID', Unid);
  Q.Open;
  if not Q.DataSet.IsEmpty then
    Result := Q.DataSet.FieldByName('UM_CODIGO').AsInteger;
end;

class procedure TProdutosAdminController.ListarAdmin(Req: THorseRequest; Res: THorseResponse);
var
  Query: iQuery;
  Busca, TipoFiltro, TipoNorm, EstadoFiltro: string;
  GrupoFiltro: Integer;
  Lista: TJSONArray;
  Item: TJSONObject;
  ValorV, ValorC, ValorCM, CustoBase, CustoFicha, Margem: Double;
begin
  TProducaoService.GarantirEstrutura;
  Query := TDatabase.Query;
  Lista := TJSONArray.Create;
  try
    Busca := '';
    if Req.Query.ContainsKey('busca') then
      Busca := UpperCase(Trim(Req.Query.Items['busca']));

    TipoFiltro := '';
    if Req.Query.ContainsKey('tipo') then
      TipoFiltro := UpperCase(Trim(Req.Query.Items['tipo']));

    EstadoFiltro := '';
    if Req.Query.ContainsKey('estado') then
      EstadoFiltro := UpperCase(Trim(Req.Query.Items['estado']));

    GrupoFiltro := 0;
    if Req.Query.ContainsKey('grupo') then
      GrupoFiltro := StrToIntDef(Trim(Req.Query.Items['grupo']), 0);

    Query.Clear;
    Query.Add('SELECT FIRST 500');
    Query.Add('  P.PRO_CODIGO, P.PRO_NOME, COALESCE(P.PRO_DESCRICAO, '''') PRO_DESCRICAO,');
    Query.Add('  COALESCE(P.PRO_CODBARRA, '''') PRO_CODBARRA, COALESCE(P.PRO_GRU, 0) PRO_GRU,');
    Query.Add('  COALESCE(G.GRU_NOME, '''') GRU_NOME,');
    Query.Add('  COALESCE(P.PRO_TIPO, '''') PRO_TIPO, COALESCE(P.PRO_EMBALAGEM, '''') PRO_EMBALAGEM,');
    Query.Add('  COALESCE(P.PRO_VALORV, 0) PRO_VALORV, COALESCE(P.PRO_VALORC, 0) PRO_VALORC,');
    Query.Add('  COALESCE(P.PRO_VALORCM, 0) PRO_VALORCM, COALESCE(P.PRO_QUANTIDADE, 0) PRO_QUANTIDADE,');
    Query.Add('  COALESCE(P.PRO_ESTADO, ''ATIVO'') PRO_ESTADO,');
    Query.Add('  COALESCE(FT.FT_CODIGO, 0) FT_CODIGO, COALESCE(FT.FT_CUSTO_UNIT, 0) FT_CUSTO_UNIT');
    Query.Add('FROM PRODUTOS P');
    Query.Add('LEFT JOIN GRUPOS G ON G.GRU_CODIGO = P.PRO_GRU');
    Query.Add('LEFT JOIN FICHA_TECNICA FT ON FT.FT_TIPO_ALVO = ''PRODUTO'' AND FT.FT_COD_ALVO = P.PRO_CODIGO AND COALESCE(FT.FT_ATIVO, ''S'') = ''S''');
    Query.Add('WHERE 1 = 1');

    if not EstadoFiltro.IsEmpty then
    begin
      if EstadoFiltro <> 'TODOS' then
      begin
        Query.Add('  AND COALESCE(P.PRO_ESTADO, ''ATIVO'') = :ESTADO');
        Query.AddParam('ESTADO', EstadoFiltro);
      end;
    end
    else
      Query.Add('  AND COALESCE(P.PRO_ESTADO, ''ATIVO'') <> ''INATIVO''');

    if (not TipoFiltro.IsEmpty) and (TipoFiltro <> 'TODOS') then
    begin
      TipoNorm := TProducaoService.NormalizarTipoProduto(TipoFiltro);
      Query.Add('  AND COALESCE(NULLIF(UPPER(TRIM(P.PRO_TIPO)), ''''), ''REVENDA'') = :TIPO');
      Query.AddParam('TIPO', TipoNorm);
    end;

    if GrupoFiltro > 0 then
    begin
      Query.Add('  AND P.PRO_GRU = :GRU');
      Query.AddParam('GRU', GrupoFiltro);
    end;

    if not Busca.IsEmpty then
    begin
      Query.Add('  AND (UPPER(P.PRO_NOME) LIKE :BUSCA OR CAST(P.PRO_CODIGO AS VARCHAR(20)) LIKE :BUSCA OR UPPER(COALESCE(P.PRO_CODBARRA, '''')) LIKE :BUSCA)');
      Query.AddParam('BUSCA', '%' + Busca + '%');
    end;

    Query.Add('ORDER BY P.PRO_NOME');
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      ValorV := Query.DataSet.FieldByName('PRO_VALORV').AsFloat;
      ValorC := Query.DataSet.FieldByName('PRO_VALORC').AsFloat;
      ValorCM := Query.DataSet.FieldByName('PRO_VALORCM').AsFloat;
      CustoFicha := Query.DataSet.FieldByName('FT_CUSTO_UNIT').AsFloat;
      CustoBase := IfThen(ValorCM > 0, ValorCM, ValorC);
      if ValorV > 0 then
        Margem := RoundTo(((ValorV - CustoBase) / ValorV) * 100.0, -2)
      else
        Margem := 0;

      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_CODIGO').AsInteger));
      Item.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
      Item.AddPair('descricao', Query.DataSet.FieldByName('PRO_DESCRICAO').AsString);
      Item.AddPair('codbarra', Query.DataSet.FieldByName('PRO_CODBARRA').AsString);
      Item.AddPair('gru', TJSONNumber.Create(Query.DataSet.FieldByName('PRO_GRU').AsInteger));
      Item.AddPair('grupo_nome', Query.DataSet.FieldByName('GRU_NOME').AsString);
      Item.AddPair('tipo', TProducaoService.NormalizarTipoProduto(Query.DataSet.FieldByName('PRO_TIPO').AsString));
      Item.AddPair('unidade', TProducaoService.NormalizarUnidade(Query.DataSet.FieldByName('PRO_EMBALAGEM').AsString));
      Item.AddPair('valorv', TJSONNumber.Create(RoundTo(ValorV, -4)));
      Item.AddPair('valorc', TJSONNumber.Create(RoundTo(ValorC, -4)));
      Item.AddPair('valorcm', TJSONNumber.Create(RoundTo(ValorCM, -4)));
      Item.AddPair('quantidade', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('PRO_QUANTIDADE').AsFloat, -2)));
      Item.AddPair('estado', Query.DataSet.FieldByName('PRO_ESTADO').AsString);
      Item.AddPair('tem_ficha', TJSONBool.Create(Query.DataSet.FieldByName('FT_CODIGO').AsInteger > 0));
      Item.AddPair('ficha_codigo', TJSONNumber.Create(Query.DataSet.FieldByName('FT_CODIGO').AsInteger));
      Item.AddPair('custo_ficha', TJSONNumber.Create(RoundTo(CustoFicha, -4)));
      Item.AddPair('margem_percentual', TJSONNumber.Create(Margem));
      Lista.AddElement(Item);
      Query.DataSet.Next;
    end;

    Res.Send<TJSONObject>(SuccessResponse(Lista, 'Produtos carregados com sucesso.'));
    Lista := nil;
  finally
    if Assigned(Lista) then
      Lista.Free;
  end;
end;

class procedure TProdutosAdminController.ListarContas(Req: THorseRequest; Res: THorseResponse);
var
  Query: iQuery;
  Lista: TJSONArray;
  Item: TJSONObject;
begin
  Query := TDatabase.Query;
  Lista := TJSONArray.Create;
  try
    Query.Clear;
    Query.Add('SELECT CON_CODIGO, CON_DESCRICAO, COALESCE(CON_SALDO, 0) CON_SALDO, COALESCE(CON_TIPO, '''') CON_TIPO');
    Query.Add('FROM CONTAS ORDER BY CON_DESCRICAO');
    Query.Open;

    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('CON_CODIGO').AsInteger));
      Item.AddPair('descricao', Query.DataSet.FieldByName('CON_DESCRICAO').AsString);
      Item.AddPair('saldo', TJSONNumber.Create(RoundTo(Query.DataSet.FieldByName('CON_SALDO').AsFloat, -2)));
      Item.AddPair('tipo', Query.DataSet.FieldByName('CON_TIPO').AsString);
      Lista.AddElement(Item);
      Query.DataSet.Next;
    end;

    Res.Send<TJSONObject>(SuccessResponse(Lista, 'Contas carregadas.'));
    Lista := nil;
  finally
    if Assigned(Lista) then
      Lista.Free;
  end;
end;

class procedure TProdutosAdminController.ListarUnidades(Req: THorseRequest; Res: THorseResponse);
var
  Query: iQuery;
  Lista: TJSONArray;
  Item: TJSONObject;
  Vistas: TList<string>;
  Padroes: TArray<string>;
  Sigla, UnidNorm: string;
begin
  Query := TDatabase.Query;
  Lista := TJSONArray.Create;
  Vistas := TList<string>.Create;
  try
    Query.Clear;
    Query.Add('SELECT UM_CODIGO, COALESCE(UM_UNIDADE, '''') UM_UNIDADE, COALESCE(UM_DESCRICAO, '''') UM_DESCRICAO FROM UNIDADE_MED ORDER BY UM_UNIDADE');
    Query.Open;
    Query.DataSet.First;
    while not Query.DataSet.Eof do
    begin
      UnidNorm := UpperCase(Trim(Query.DataSet.FieldByName('UM_UNIDADE').AsString));
      if not UnidNorm.IsEmpty then
      begin
        Vistas.Add(UnidNorm);
        Item := TJSONObject.Create;
        Item.AddPair('codigo', TJSONNumber.Create(Query.DataSet.FieldByName('UM_CODIGO').AsInteger));
        Item.AddPair('unidade', UnidNorm);
        Item.AddPair('descricao', Query.DataSet.FieldByName('UM_DESCRICAO').AsString);
        Lista.AddElement(Item);
      end;
      Query.DataSet.Next;
    end;

    Padroes := ['UN', 'KG', 'G', 'L', 'ML'];
    for Sigla in Padroes do
    begin
      if not Vistas.Contains(Sigla) then
      begin
        Item := TJSONObject.Create;
        Item.AddPair('codigo', TJSONNumber.Create(0));
        Item.AddPair('unidade', Sigla);
        Item.AddPair('descricao', Sigla);
        Lista.AddElement(Item);
      end;
    end;

    Res.Send<TJSONObject>(SuccessResponse(Lista, 'Unidades carregadas.'));
    Lista := nil;
  finally
    Vistas.Free;
    if Assigned(Lista) then
      Lista.Free;
  end;
end;

class procedure TProdutosAdminController.GetImagemProduto(Req: THorseRequest;
  Res: THorseResponse);
var
  Query: iQuery;
begin
  Query := TDatabase.Query;
  Query.Add('SELECT PRO_CAMINHO_IMAGEM FROM PRODUTOS WHERE PRO_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', Req.Params.Items['codigo'].ToInteger);
  Query.Open;
  Res.Send<TJSONObject>(
    TJSONObject.Create.AddPair('imagem', Query.DataSet.FieldByName('PRO_CAMINHO_IMAGEM').AsString)
  );
end;

class procedure TProdutosAdminController.GetImagemCategoria(Req: THorseRequest;
  Res: THorseResponse);
var
  Query: iQuery;
begin
  Query := TDatabase.Query;
  Query.Add('SELECT GRU_CAMINHO_IMAGEM FROM GRUPOS WHERE GRU_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', Req.Params.Items['codigo'].ToInteger);
  Query.Open;
  Res.Send<TJSONObject>(
    TJSONObject.Create.AddPair('imagem', Query.DataSet.FieldByName('GRU_CAMINHO_IMAGEM').AsString)
  );
end;

class procedure TProdutosAdminController.PostProduto(Req: THorseRequest;
  Res: THorseResponse);
var
  Produto: TProdutos;
  Body: TJSONObject;
  Texto, Unid: string;
  Numero: Double;
  Inteiro, CodUM: Integer;
begin
  Body := Req.Body<TJSONObject>;
  Produto := TProdutos.Create(TDatabase.Connection);
  try
    Produto.CriaTabela;
    Produto.Codigo := GeraCodigo('PRODUTOS', 'PRO_CODIGO');
    Produto.Estado := 'ATIVO';
    Produto.Tipo := 'REVENDA';
    Produto.Embalagem := 'UN';
    Produto.Estoque := 'S';
    Produto.Datauc := Date;
    Produto.Dataua := Date;
    Produto.Iat := 'A';
    Produto.Ippt := 'T';

    if Body.TryGetValue<string>('nome', Texto) then Produto.Nome := Copy(Trim(Texto), 1, 50);
    if Body.TryGetValue<Double>('valorv', Numero) then Produto.Valorv := Numero
    else if Body.TryGetValue<Double>('valor', Numero) then Produto.Valorv := Numero;
    if Body.TryGetValue<Double>('valorc', Numero) then Produto.Valorc := Numero;
    if Body.TryGetValue<Double>('valorcm', Numero) then Produto.Valorcm := Numero;
    if (Produto.Valorc <= 0) and (Produto.Valorcm > 0) then Produto.Valorc := Produto.Valorcm;
    if (Produto.Valorcm <= 0) and (Produto.Valorc > 0) then Produto.Valorcm := Produto.Valorc;
    if Body.TryGetValue<Double>('quantidade', Numero) then Produto.Quantidade := Numero;
    if Body.TryGetValue<string>('descricao', Texto) then Produto.Descricao := Copy(Trim(Texto), 1, 30);
    if Body.TryGetValue<Integer>('gru', Inteiro) then Produto.Gru := Inteiro;
    if Body.TryGetValue<string>('estado', Texto) then Produto.Estado := Copy(UpperCase(Trim(Texto)), 1, 8);
    if Body.TryGetValue<string>('codbarra', Texto) then Produto.Codbarra := Copy(Trim(Texto), 1, 30);
    if Body.TryGetValue<string>('caminho_imagem', Texto) then Produto.Caminho_imagem := Texto;
    if Body.TryGetValue<string>('tipo', Texto) then
      Produto.Tipo := TProducaoService.NormalizarTipoProduto(Texto);
    if Body.TryGetValue<string>('unidade', Texto) then
    begin
      Unid := TProducaoService.NormalizarUnidade(Texto);
      Produto.Embalagem := Copy(Unid, 1, 10);
      CodUM := ObterCodigoUnidadeMed(Unid);
      if CodUM > 0 then Produto.Um := CodUM;
    end;
    if Body.TryGetValue<string>('estoque', Texto) then Produto.Estoque := Copy(UpperCase(Trim(Texto)), 1, 5);

    if Produto.Gru <= 0 then
      Produto.Gru := ObterGrupoPadrao;

    if Produto.Nome.Trim.IsEmpty then
      raise Exception.Create('Nome do produto e obrigatorio.');
    if Produto.Gru <= 0 then
      raise Exception.Create('Grupo do produto e obrigatorio.');

    Produto.SalvaNoBanco(1);
    Res.Status(THTTPStatus.Created).Send<TJSONObject>(Produto.ToJsonObject);
  finally
    Produto.DisposeOf;
  end;
end;

class procedure TProdutosAdminController.PutProduto(Req: THorseRequest;
  Res: THorseResponse);
var
  Produto: TProdutos;
  Body: TJSONObject;
  Codigo, Inteiro, CodUM: Integer;
  Texto, Unid: string;
  Numero, OldValorCM, OldValorC: Double;
  AlterouCusto: Boolean;
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Transacao: TFDTransaction;
  Recalculadas: TJSONArray;
  RespJson: TJSONObject;
begin
  TProducaoService.GarantirEstrutura;
  Body := Req.Body<TJSONObject>;
  if not Body.TryGetValue<Integer>('codigo', Codigo) then
    raise Exception.Create('Codigo do produto e obrigatorio.');

  AlterouCusto := False;
  Produto := TProdutos.Create(TDatabase.Connection);
  try
    Produto.CriaTabela;
    Produto.BuscaDadosTabela(Codigo);
    OldValorCM := Produto.Valorcm;
    OldValorC := Produto.Valorc;

    if Body.TryGetValue<string>('nome', Texto) then Produto.Nome := Copy(Trim(Texto), 1, 50);
    if Body.TryGetValue<Double>('valorv', Numero) then Produto.Valorv := Numero
    else if Body.TryGetValue<Double>('valor', Numero) then Produto.Valorv := Numero;
    if Body.TryGetValue<Double>('valorc', Numero) then
    begin
      Produto.Valorc := Numero;
      AlterouCusto := True;
    end;
    if Body.TryGetValue<Double>('valorcm', Numero) then
    begin
      Produto.Valorcm := Numero;
      AlterouCusto := True;
    end;
    if Body.TryGetValue<Double>('quantidade', Numero) then Produto.Quantidade := Numero;
    if Body.TryGetValue<string>('descricao', Texto) then Produto.Descricao := Copy(Trim(Texto), 1, 30);
    if Body.TryGetValue<Integer>('gru', Inteiro) and (Inteiro > 0) then Produto.Gru := Inteiro;
    if Body.TryGetValue<string>('estado', Texto) then Produto.Estado := Copy(UpperCase(Trim(Texto)), 1, 8);
    if Body.TryGetValue<string>('codbarra', Texto) then Produto.Codbarra := Copy(Trim(Texto), 1, 30);
    if Body.TryGetValue<string>('caminho_imagem', Texto) then Produto.Caminho_imagem := Texto;
    if Body.TryGetValue<string>('tipo', Texto) then
      Produto.Tipo := TProducaoService.NormalizarTipoProduto(Texto);
    if Body.TryGetValue<string>('unidade', Texto) then
    begin
      Unid := TProducaoService.NormalizarUnidade(Texto);
      Produto.Embalagem := Copy(Unid, 1, 10);
      CodUM := ObterCodigoUnidadeMed(Unid);
      if CodUM > 0 then Produto.Um := CodUM;
    end;
    if Body.TryGetValue<string>('estoque', Texto) then Produto.Estoque := Copy(UpperCase(Trim(Texto)), 1, 5);
    Produto.Dataua := Date;

    Produto.SalvaNoBanco(1);

    RespJson := Produto.ToJsonObject;
    if AlterouCusto and ((Abs(Produto.Valorcm - OldValorCM) > 0.0001) or (Abs(Produto.Valorc - OldValorC) > 0.0001)) then
    begin
      Recalculadas := TJSONArray.Create;
      BancoDados := TDatabase.Connection;
      IndiceConexao := BancoDados.Connected;
      Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
      Transacao := TFDTransaction.Create(nil);
      try
        Transacao.Connection := Conexao;
        Transacao.StartTransaction;
        try
          TProducaoService.RecalcularEmCascata(Conexao, Transacao, Codigo, Recalculadas);
          Transacao.Commit;
        except
          if Transacao.Active then
            Transacao.Rollback;
        end;
      finally
        Transacao.DisposeOf;
        BancoDados.Disconnected(IndiceConexao);
      end;
      RespJson.AddPair('fichas_recalculadas', Recalculadas);
    end;

    Res.Send<TJSONObject>(RespJson);
  finally
    Produto.DisposeOf;
  end;
end;

class procedure TProdutosAdminController.DeleteProduto(Req: THorseRequest;
  Res: THorseResponse);
var
  Produto: TProdutos;
begin
  Produto := TProdutos.Create(TDatabase.Connection);
  try
    Produto.Apagar(Req.Params.Items['codigo'].ToInteger);
    Res.Send('').Status(THTTPStatus.NoContent);
  finally
    Produto.DisposeOf;
  end;
end;

class procedure TProdutosAdminController.Registrar;
begin
  THorse.Get('/v1/produtos/admin', ListarAdmin);
  THorse.Get('/v1/contas', ListarContas);
  THorse.Get('/v1/unidades', ListarUnidades);
  THorse.Post('/v1/produtos', PostProduto);
  THorse.Put('/v1/produtos', PutProduto);
  THorse.Delete('/v1/produtos/:codigo', DeleteProduto);
  THorse.Get('/v1/produtos/:codigo/imagem', GetImagemProduto);
  THorse.Get('/v1/categorias/:codigo/imagem', GetImagemCategoria);
end;

end.
