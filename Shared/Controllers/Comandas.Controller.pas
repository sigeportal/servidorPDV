unit Comandas.Controller;

interface

uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  Classes,
  SysUtils,
  System.Json,
  UnitConnection.Model.Interfaces,
  DataSet.Serialize,
  UnitComanda.Model,
  UnitComplemento.Model;

type
  TComandasController = class
  private
    class function BuscaDadosGrade(CodGrade: integer): TJSONObject;
  public
    class procedure Registrar;
    class procedure Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetPorCodigo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Post(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure EncerrarComanda(Req: THorseRequest; Res: THorseResponse);
    class procedure AtualizarEstado(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure AtualizarComanda(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure DeletarItemComanda(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure DeletarComplementos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure GetItemComPro(Req: THorseRequest; Res: THorseResponse; Next: TProc);
  end;

implementation

{ TComandasController }

uses UnitConstants, UnitDatabase, UnitCpAdicionais.Model, UnitCpOpcoes.Model, 
  System.StrUtils;

class procedure TComandasController.AtualizarComanda(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Codigo: integer;
  CodigoComanda: integer;
  Comanda: TModelComanda;
  i: integer;
  Item: TModelItens;
  TotalComanda: Currency;
  CodigoComPro: integer;
  Complementos: TArray<TModelComplemento>;
  c: integer;
  TotalComplementos: Currency;
  Opcoes: TArray<TModelOpcoesNiveis>;
  o: Integer;
  TotalOpcoesNiveis: Currency;
begin
  if Req.Params.Count = 0 then
    raise Exception.Create('Paramentro "Codigo" não informado!');
  Codigo  := Req.Params.Items['codigo'].ToInteger;
  Comanda := TModelComanda.FromJsonString(Req.Body);
  Query   := TDatabase.Query;
  Query.Clear;
  Query.Add('SELECT COM_CODIGO FROM COMANDAS WHERE COM_CODIGO = (SELECT MAX(COM_CODIGO) FROM COMANDAS WHERE COM_DATA_FECHAMENTO IS NULL AND COM_MESA = :CODIGO)');
  Query.AddParam('CODIGO', Codigo);
  Query.Open;
  CodigoComanda := Query.DataSet.FieldByName('COM_CODIGO').AsInteger;
  For i := Low(Comanda.Itens) to High(Comanda.Itens) do
  begin
    Item := Comanda.Itens[i];
    Query.Clear;
    Query.Add('UPDATE OR INSERT INTO COM_PRO ');
    Query.Add('(CP_CODIGO, CP_COM, CP_PRO, CP_QUANTIDADE, CP_VALOR, CP_GRA, CP_OBS, CP_ESTADO, CP_USU, CP_ID_AGRUPAMENTO)');
    Query.Add('VALUES (GEN_ID(GEN_CP_CODIGO, 1), :COM, :PRO, :QUANTIDADE, :VALOR, :GRA, :OBS, :ESTADO, :USUARIO, :ID_AGRUPAMENTO)');
    Query.Add('MATCHING (CP_CODIGO) RETURNING (CP_CODIGO)');
    Query.AddParam('COM', CodigoComanda);
    Query.AddParam('PRO', Item.Produto);
    Query.AddParam('QUANTIDADE', Item.Quantidade);
    Query.AddParam('VALOR', Item.Valor);
    Query.AddParam('GRA', Item.Grade);
    Query.AddParam('OBS', Item.Obs);
    Query.AddParam('ESTADO', 'A');
    Query.AddParam('USUARIO', Item.usuario);
    Query.AddParam('ID_AGRUPAMENTO', Item.IdAgrupamento);
    Query.Open();
    if not Query.DataSet.IsEmpty then
      CodigoComPro := Query.DataSet.FieldByName('CP_CODIGO').AsInteger;
    if CodigoComPro > 0 then
    begin
      Complementos := Comanda.Itens[i].Complementos;
      for c        := Low(Complementos) to High(Complementos) do
      begin
        Query.Clear;
        Query.Add('INSERT INTO CP_ADICIONAIS (CA_CODIGO, CA_CP, CA_ADI, CA_QUANTIDADE)');
        Query.Add('VALUES (GEN_ID(GEN_CP_ADICIONAIS, 1), :CP, :ADI, :QUANTIDADE);');
        Query.AddParam('CP', CodigoComPro);
        Query.AddParam('ADI', Complementos[c].Codigo);
        Query.AddParam('QUANTIDADE', Complementos[c].Quantidade);
        Query.ExecSQL;
      end;
      Opcoes := Comanda.Itens[i].OpcoesNiveis;
      for o        := Low(Opcoes) to High(Opcoes) do
      begin
        Query.Clear;
        Query.Add('INSERT INTO CP_OPCOES (CO_CODIGO, CO_CP, CO_NI, CO_QUANTIDADE, CO_VALOR, CO_NOME, CO_ATIVO, CO_SELECIONADO, CO_OP)');
        Query.Add('VALUES (GEN_ID(GEN_CP_OPCOES, 1), :CP, :NI, :QUANTIDADE, :VALOR, :NOME, :ATIVO, :SELECIONADO, :COD_OPCAO);');
        Query.AddParam('CP', CodigoComPro);
        Query.AddParam('NI', Opcoes[o].codNivel);
        Query.AddParam('QUANTIDADE', Opcoes[o].Quantidade);
        Query.AddParam('VALOR', Opcoes[o].ValorAdicional);
        Query.AddParam('NOME', Opcoes[o].nome);
        Query.AddParam('ATIVO', Opcoes[o].ativoStr);
        Query.AddParam('SELECIONADO', ifthen(Opcoes[o].selecionado, 'S', 'N'));
        Query.AddParam('COD_OPCAO', Opcoes[o].codigo);
        Query.ExecSQL;
      end;
    end;
  end;
  Query.Clear;
  Query.Add('SELECT SUM(CP_VALOR) TOTAL, SUM(ADI_VALOR * CA_QUANTIDADE) COMPLEMENTOS');
  Query.Add('FROM COM_PRO JOIN COMANDAS ON CP_COM = COM_CODIGO');
  Query.Add('LEFT JOIN CP_ADICIONAIS ON CA_CP = CP_CODIGO');
  Query.Add('LEFT JOIN ADICIONAIS ON CA_ADI = ADI_CODIGO');
  Query.Add('WHERE COM_CODIGO = :CODIGO AND CP_ESTADO <> ''E''');
  Query.AddParam('CODIGO', CodigoComanda);
  Query.Open();
  TotalComanda      := Query.DataSet.FieldByName('TOTAL').AsCurrency;
  TotalComplementos := Query.DataSet.FieldByName('COMPLEMENTOS').AsCurrency;
  // soma opcoes niveis
  Query.Clear;
  Query.Add('SELECT SUM(CO_VALOR * CO_QUANTIDADE) OPCOES');
  Query.Add('FROM COM_PRO JOIN COMANDAS ON CP_COM = COM_CODIGO');
  Query.Add('LEFT JOIN CP_OPCOES ON CO_CP = CP_CODIGO');
  Query.Add('WHERE COM_CODIGO = :CODIGO AND CP_ESTADO <> ''E''');
  Query.AddParam('CODIGO', CodigoComanda);
  Query.Open();
  TotalOpcoesNiveis := Query.DataSet.FieldByName('OPCOES').AsCurrency;
  // Atualiza comandas
  Query.Clear;
  Query.Add('UPDATE COMANDAS SET COM_VALOR = :VALOR WHERE COM_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', CodigoComanda);
  Query.AddParam('VALOR', TotalComanda + TotalComplementos + TotalOpcoesNiveis);
  Query.ExecSQL;
  // Atualiza o estado da mesa
  Query.Clear;
  Query.Add('UPDATE MESAS SET MES_ESTADO = ''O'' WHERE MES_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', Codigo);
  Query.ExecSQL;
  Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Comanda Atualizada com sucesso')).Status(THTTPStatus.OK);
end;

class function TComandasController.BuscaDadosGrade(CodGrade: integer): TJSONObject;
var
  Query: iQuery;
begin
  Result := TJSONObject.Create;
  if CodGrade > 0 then
  begin
    Query := TDatabase.Query;
    Query.Add('SELECT GRA_CODIGO codigo, TAM_SIGLA tamanho, GRA_VALOR valor FROM GRADES JOIN TAMANHOS ON GRA_TAM = TAM_CODIGO');
    Query.Add('WHERE GRA_CODIGO = :CODIGO');
    Query.AddParam('CODIGO', CodGrade);
    Query.Open();
    Result := Query.DataSet.ToJSONObject;
  end;
end;

class procedure TComandasController.DeletarComplementos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Codigo: integer;
begin
  if Req.Params.Count > 0 then
  begin
    Codigo := Req.Params.Items['codigo'].ToInteger();
    Query  := TDatabase.Query;
    // deleta cp adicionais
    Query.Clear;
    Query.Add('DELETE FROM CP_ADICIONAIS WHERE CA_CP = :CODIGO');
    Query.AddParam('CODIGO', Codigo);
    Query.ExecSQL;
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Complementos excluidos com sucesso!')).Status(THTTPStatus.OK);
  end
  else
    Res.Send<TJSONObject>(TJSONObject.Create().AddPair('error', 'Codigo da com_pro não informado')).Status(THTTPStatus.BadRequest);
end;

class procedure TComandasController.DeletarItemComanda(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Codigo: integer;
  CodigoComanda: integer;
  TotalComanda: Currency;
  TotalComplementos: Currency;
  CodigoMesa: integer;
  IdAgrupamento: string;
begin
  if Req.Params.Count > 0 then
  begin
    Codigo := Req.Params.Items['codigo'].ToInteger();
    Query  := TDatabase.Query;
    // busca o codigo da comanda
    Query.Clear;
    Query.Add('SELECT CP_COM, CP_ID_AGRUPAMENTO FROM COM_PRO WHERE CP_CODIGO = :CODIGO');
    Query.AddParam('CODIGO', Codigo);
    Query.Open();
    CodigoComanda := Query.DataSet.FieldByName('CP_COM').AsInteger;
    //se tem id agrupamento então poe estado E = excluido em todos com mesmo ID
    IdAgrupamento := Query.DataSet.FieldByName('CP_ID_AGRUPAMENTO').AsString;
    /// /
    Query.Clear;
    if IdAgrupamento.IsEmpty then
    begin
	    Query.Add('UPDATE COM_PRO SET CP_ESTADO = ''E'' WHERE CP_CODIGO = :CODIGO');
      Query.AddParam('CODIGO', Codigo);
    end else
    begin
    	Query.Add('UPDATE COM_PRO SET CP_ESTADO = ''E'' WHERE CP_ID_AGRUPAMENTO = :ID');
      Query.AddParam('ID', IdAgrupamento);    
    end;
    Query.ExecSQL;
    // deleta cp adicionais
    Query.Clear;
    Query.Add('DELETE FROM CP_ADICIONAIS WHERE CA_CP = :CODIGO');
    Query.AddParam('CODIGO', Codigo);
    Query.ExecSQL;
    // soma comanda
    Query.Clear;
    Query.Add('SELECT SUM(CP_VALOR) TOTAL');
    Query.Add('FROM COM_PRO JOIN COMANDAS ON CP_COM = COM_CODIGO');
    Query.Add('WHERE COM_CODIGO = :CODIGO AND CP_ESTADO <> ''E''');
    Query.AddParam('CODIGO', CodigoComanda);
    Query.Open();
    TotalComanda := Query.DataSet.FieldByName('TOTAL').AsCurrency;
    // verifica se ainda existe itens na comanda
    Query.Clear;
    Query.Add('SELECT SUM(ADI_VALOR * CA_QUANTIDADE) COMPLEMENTOS');
    Query.Add('FROM COM_PRO JOIN COMANDAS ON CP_COM = COM_CODIGO');
    Query.Add('LEFT JOIN CP_ADICIONAIS ON CA_CP = CP_CODIGO');
    Query.Add('LEFT JOIN ADICIONAIS ON CA_ADI = ADI_CODIGO');
    Query.Add('WHERE COM_CODIGO = :CODIGO AND CP_ESTADO <> ''E''');
    Query.AddParam('CODIGO', CodigoComanda);
    Query.Open();
    TotalComplementos := Query.DataSet.FieldByName('COMPLEMENTOS').AsCurrency;
    if TotalComanda > 0 then
    begin
      // Atualiza comandas
      Query.Clear;
      Query.Add('UPDATE COMANDAS SET COM_VALOR = :VALOR WHERE COM_CODIGO = :CODIGO');
      Query.AddParam('CODIGO', CodigoComanda);
      Query.AddParam('VALOR', TotalComanda + TotalComplementos);
      Query.ExecSQL;
    end
    else
    begin
      // Atualiza comandas
      Query.Clear;
      Query.Add('UPDATE COMANDAS SET COM_DATA_FECHAMENTO = :DATA WHERE COM_CODIGO = :CODIGO');
      Query.AddParam('DATA', Date);
      Query.AddParam('CODIGO', CodigoComanda);
      Query.ExecSQL;
      // busca codigo da mesa
      Query.Clear;
      Query.Add('SELECT COM_MESA FROM COMANDAS WHERE COM_CODIGO = :CODIGO');
      Query.AddParam('CODIGO', CodigoComanda);
      Query.Open;
      CodigoMesa := Query.DataSet.FieldByName('COM_MESA').AsInteger;
      // Atualiza o estado da mesa
      Query.Clear;
      Query.Add('UPDATE MESAS SET MES_ESTADO = ''A'' WHERE MES_CODIGO = :CODIGO');
      Query.AddParam('CODIGO', CodigoMesa);
      Query.ExecSQL;
    end;
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Item excluido com sucesso!')).Status(THTTPStatus.OK);
  end
  else
    Res.Send<TJSONObject>(TJSONObject.Create().AddPair('error', 'Codigo da com_pro não informado')).Status(THTTPStatus.BadRequest);
end;

class procedure TComandasController.EncerrarComanda(Req: THorseRequest; Res: THorseResponse);
var
  Query: iQuery;
  CodMesa: Integer;
  CodigoComanda: Integer;
begin
	CodMesa := Req.Params.Items['codigo'].ToInteger();
	Query := TDatabase.Query;
	// Tratamento para atualizar estado da mesa faturada, mudando para estado 'A' de Aberto
  Query.Clear;
  Query.Add('UPDATE MESAS SET MES_ESTADO = :ESTADO WHERE MES_CODIGO = :MESA');
  Query.AddParam('ESTADO', 'A');
  Query.AddParam('MESA', CodMesa);
  Query.ExecSQL;
  //busco o cod da comanda
  Query  := TDatabase.Query;
  Query.Clear;
  Query.Add('SELECT COM_CODIGO FROM COMANDAS WHERE COM_CODIGO = (SELECT MAX(COM_CODIGO) FROM COMANDAS WHERE COM_DATA_FECHAMENTO IS NULL AND COM_MESA = :MESA)');
  Query.AddParam('MESA', CodMesa);
  Query.Open;
  CodigoComanda := Query.DataSet.FieldByName('COM_CODIGO').AsInteger;
  // Preenchendo a data de fechamento da comanda
  Query.Clear;
  Query.Add('UPDATE COMANDAS SET COM_DATA_FECHAMENTO = :DATA_FECHAMENTO, COM_HORA_FECHAMENTO = :HORA_FECHAMENTO WHERE COM_CODIGO = :CODIGO');
  Query.AddParam('DATA_FECHAMENTO', Date);
  Query.AddParam('HORA_FECHAMENTO', Now);
  Query.AddParam('CODIGO', CodigoComanda);
  Query.ExecSQL;
  Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Comanda encerrada com sucesso!')).Status(THTTPStatus.OK);
end;

class procedure TComandasController.AtualizarEstado(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Codigo: integer;
  Status: string;
begin
  if Req.Params.Count > 0 then
  begin
    Codigo := Req.Params.Items['codigo'].ToInteger();
    Status := Req.Params.Items['status'];
    Query  := TDatabase.Query;
    Query.Clear;
    Query.Add('UPDATE MESAS SET MES_ESTADO = :STATUS WHERE MES_CODIGO = :CODIGO');
    Query.AddParam('CODIGO', Codigo);
    Query.AddParam('STATUS', Status);
    Query.ExecSQL;
    Res.Send<TJSONObject>(TJSONObject.Create.AddPair('message', 'Mesa ' + Codigo.ToString + ' encerrada com sucesso')).Status(THTTPStatus.OK);
  end
  else
    Res.Send<TJSONObject>(TJSONObject.Create().AddPair('error', 'Codigo da comanda não informado')).Status(THTTPStatus.BadRequest);
end;

class procedure TComandasController.Get(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  QueryComandas, QueryComPro, QueryComplementos: iQuery;
  CodigoComanda: integer;
  Comandas: TJSONArray;
  Comanda: TJSONObject;
  Produtos: TJSONArray;
  Item: TJSONObject;
  Itens: TJSONArray;
  Complemento: TJSONObject;
  Complementos: TJSONArray;
  QueryOpcoesNiveis: iQuery;
  Opcoes: TJSONArray;
  Opcao: TJSONObject;
  CpOpcoes: TCpOpcoes;
  CpAdicionais: TCpAdicionais;
begin
  CpOpcoes := TCpOpcoes.Create(TDatabase.Connection);
  try
    CpOpcoes.CriaTabela;
  finally
    CpOpcoes.DisposeOf;
  end;
  CpAdicionais := TCpAdicionais.Create(TDatabase.Connection);
  try
    CpAdicionais.CriaTabela;
  finally
    CpAdicionais.DisposeOf;
  end;
  Comandas      := TJSONArray.Create;
  QueryComandas := TDatabase.Query;
  QueryComandas.Clear;
  QueryComandas.Add('SELECT COM_CODIGO, COM_MESA, COM_DATA_ABERTURA, COM_HORA_ABERTURA, COM_DATA_FECHAMENTO, COM_HORA_FECHAMENTO, COM_DATAC, COM_VALOR, COM_COMANDA FROM COMANDAS');
  QueryComandas.Add('WHERE COM_DATA_FECHAMENTO IS NULL');
  QueryComandas.Open;
  QueryComandas.DataSet.First;
  while not QueryComandas.DataSet.Eof do
  begin
    CodigoComanda := QueryComandas.DataSet.FieldByName('COM_CODIGO').AsInteger;
    Comanda       := QueryComandas.DataSet.ToJSONObject;
    // itens
    QueryComPro := TDatabase.Query;
    QueryComPro.Clear;
    QueryComPro.Add('SELECT CP_CODIGO, CP_COM, CP_PRO, CP_QUANTIDADE, CP_VALOR, ');
    QueryComPro.Add('CP_GRA, CP_OBS, CP_ESTADO, PRO_NOME, CP_USU, CP_ID_AGRUPAMENTO ');
    QueryComPro.Add('FROM COM_PRO CP JOIN PRODUTOS ON PRO_CODIGO = CP_PRO ');
    QueryComPro.Add('WHERE CP_COM = :CODIGO AND CP_ESTADO <> ''E'' ORDER BY CP_CODIGO');
    QueryComPro.AddParam('CODIGO', CodigoComanda);
    QueryComPro.Open;
    Itens := TJSONArray.Create;
    QueryComPro.DataSet.First;
    while not QueryComPro.DataSet.Eof do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('cpCodigo', TJSONNumber.Create(QueryComPro.DataSet.FieldByName('CP_CODIGO').AsInteger));
      Item.AddPair('cpCom', TJSONNumber.Create(QueryComPro.DataSet.FieldByName('CP_COM').AsInteger));
      Item.AddPair('cpPro', TJSONNumber.Create(QueryComPro.DataSet.FieldByName('CP_PRO').AsInteger));
      Item.AddPair('cpQuantidade', TJSONNumber.Create(QueryComPro.DataSet.FieldByName('CP_QUANTIDADE').AsFloat));
      Item.AddPair('cpValor', TJSONNumber.Create(QueryComPro.DataSet.FieldByName('CP_VALOR').AsCurrency));
      Item.AddPair('cpGra', TJSONNumber.Create(QueryComPro.DataSet.FieldByName('CP_GRA').AsInteger));
      Item.AddPair('cpObs', QueryComPro.DataSet.FieldByName('CP_OBS').AsString);
      Item.AddPair('cpEstado', QueryComPro.DataSet.FieldByName('CP_ESTADO').AsString);
      Item.AddPair('nome', QueryComPro.DataSet.FieldByName('PRO_NOME').AsString);
      Item.AddPair('gradeProduto', BuscaDadosGrade(QueryComPro.DataSet.FieldByName('CP_GRA').AsInteger));
      Item.AddPair('usuario', TJSONNumber.Create(QueryComPro.DataSet.FieldByName('CP_USU').AsInteger));
      Item.AddPair('idAgrupamento', QueryComPro.DataSet.FieldByName('CP_ID_AGRUPAMENTO').AsString);
      QueryComplementos := TDatabase.Query;
      QueryComplementos.Clear;
      QueryComplementos.Add('SELECT CA_CODIGO, CA_CP, CA_ADI, CA_QUANTIDADE, ADI_NOME, ADI_VALOR FROM CP_ADICIONAIS JOIN ADICIONAIS ON CA_ADI = ADI_CODIGO WHERE CA_CP = :COM_PRO ORDER BY CA_CODIGO');
      QueryComplementos.AddParam('COM_PRO', QueryComPro.DataSet.FieldByName('CP_CODIGO').AsInteger);
      QueryComplementos.Open;
      QueryComplementos.DataSet.First;
      Complementos := TJSONArray.Create;
      while not QueryComplementos.DataSet.Eof do
      begin
        Complemento := TJSONObject.Create;
        Complemento.AddPair('codigo', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('CA_CODIGO').AsInteger));
        Complemento.AddPair('nome', QueryComplementos.DataSet.FieldByName('ADI_NOME').AsString);
        Complemento.AddPair('valor', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('ADI_VALOR').AsCurrency));
        Complemento.AddPair('quantidade', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('CA_QUANTIDADE').AsFloat));
        Complementos.AddElement(Complemento);
        QueryComplementos.DataSet.Next;
      end;
      Item.AddPair('complementos', Complementos);
      Itens.AddElement(Item);
       //Opcoes niveis
      QueryOpcoesNiveis := TDatabase.Query;
      QueryOpcoesNiveis.Clear;
      QueryOpcoesNiveis.Add('SELECT CO_CODIGO, CO_CP, CO_NI, CO_QUANTIDADE, CO_VALOR, CO_NOME, CO_ATIVO, CO_SELECIONADO, CO_OP');
      QueryOpcoesNiveis.Add('FROM CP_OPCOES WHERE CO_CP = :COM_PRO ORDER BY CO_CODIGO');    
      QueryOpcoesNiveis.AddParam('COM_PRO', QueryComPro.DataSet.FieldByName('CP_CODIGO').AsInteger);
      QueryOpcoesNiveis.Open;
      Opcoes := TJSONArray.Create;
      QueryOpcoesNiveis.DataSet.First;
      while not QueryOpcoesNiveis.DataSet.Eof do
      begin
        Opcao := TJSONObject.Create;
        Opcao.AddPair('codigo', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_OP').AsInteger));
        Opcao.AddPair('nome', QueryOpcoesNiveis.DataSet.FieldByName('CO_NOME').AsString);
        Opcao.AddPair('valorAdicional', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_VALOR').AsCurrency));
        Opcao.AddPair('ativo', TJSONBool.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_ATIVO').AsString.Contains('S')));
        Opcao.AddPair('ativoStr', QueryOpcoesNiveis.DataSet.FieldByName('CO_ATIVO').AsString);
        Opcao.AddPair('codNivel', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_NI').AsInteger));
        Opcao.AddPair('selecionado', TJSONBool.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_SELECIONADO').AsString.Contains('S')));
        Opcao.AddPair('quantidade', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_QUANTIDADE').AsFloat));
        Opcoes.AddElement(Opcao);
        QueryOpcoesNiveis.DataSet.Next;
      end;
      Item.AddPair('OpcoesNiveis', Opcoes);
      QueryComPro.DataSet.Next;
    end;
    Comanda.AddPair('itens', Itens);
    Comandas.AddElement(Comanda);
    QueryComandas.DataSet.Next;
  end;
  Res.Send<TJSONArray>(Comandas);
end;

class procedure TComandasController.GetItemComPro(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  CodigoComPro: integer;
  QueryComplementos: iQuery;
  Item: TJSONObject;
  Complementos: TJSONArray;
  Complemento: TJSONObject;
  QueryProduto: iQuery;
  oProduto: TJSONObject;
  QueryOpcoesNiveis: iQuery;
  Opcoes: TJSONArray;
  Opcao: TJSONObject;
begin
  // Codigo com_pro
  CodigoComPro := Req.Params.Items['codigo'].ToInteger();
  Query        := TDatabase.Query;
  Query.Clear;
  Query.Add('SELECT CP_CODIGO, CP_COM, CP_PRO, CP_QUANTIDADE, CP_VALOR, CP_GRA, ');
  Query.Add('CP_OBS, CP_ESTADO, PRO_NOME, CP_USU, CP_ID_AGRUPAMENTO ');
  Query.Add('FROM COM_PRO CP JOIN PRODUTOS ON PRO_CODIGO = CP_PRO ');
  Query.Add('WHERE CP_CODIGO = :CODIGO ORDER BY CP_CODIGO');
  Query.AddParam('CODIGO', CodigoComPro);
  Query.Open;
  Query.DataSet.First;
  while not Query.DataSet.Eof do
  begin
    oProduto     := TJSONObject.Create;
    QueryProduto := TDatabase.Query;
    QueryProduto.Add('SELECT PRO_CODIGO codigo, PRO_NOME nome, PRO_VALORV valor, GRU_G1 categoria ');
    QueryProduto.Add('FROM PRODUTOS LEFT JOIN GRUPOS ON PRO_GRU = GRU_CODIGO WHERE PRO_CODIGO = :CODIGO');
    QueryProduto.AddParam('CODIGO', Query.DataSet.FieldByName('CP_PRO').AsInteger);
    QueryProduto.Open;
    Item := TJSONObject.Create;
    Item.AddPair('cpCodigo', TJSONNumber.Create(Query.DataSet.FieldByName('CP_CODIGO').AsInteger));
    Item.AddPair('cpCom', TJSONNumber.Create(Query.DataSet.FieldByName('CP_COM').AsInteger));
    Item.AddPair('produto', QueryProduto.DataSet.ToJSONObject());
    Item.AddPair('cpQuantidade', TJSONNumber.Create(Query.DataSet.FieldByName('CP_QUANTIDADE').AsFloat));
    Item.AddPair('cpValor', TJSONNumber.Create(Query.DataSet.FieldByName('CP_VALOR').AsCurrency));
    Item.AddPair('cpGra', TJSONNumber.Create(Query.DataSet.FieldByName('CP_GRA').AsInteger));
    Item.AddPair('cpObs', Query.DataSet.FieldByName('CP_OBS').AsString);
    Item.AddPair('cpEstado', Query.DataSet.FieldByName('CP_ESTADO').AsString);
    Item.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
    Item.AddPair('usuario', TJSONNumber.Create(Query.DataSet.FieldByName('CP_USU').AsInteger));
    Item.AddPair('idAgrupamento', Query.DataSet.FieldByName('CP_ID_AGRUPAMENTO').AsString);
    QueryComplementos := TDatabase.Query;
    QueryComplementos.Clear;
    QueryComplementos.Add('SELECT CA_CODIGO, CA_CP, CA_ADI, CA_QUANTIDADE, ADI_NOME, ADI_VALOR FROM CP_ADICIONAIS JOIN ADICIONAIS ON CA_ADI = ADI_CODIGO WHERE CA_CP = :COM_PRO');
    QueryComplementos.AddParam('COM_PRO', Query.DataSet.FieldByName('CP_CODIGO').AsInteger);
    QueryComplementos.Open;
    QueryComplementos.DataSet.First;
    Complementos := TJSONArray.Create;
    while not QueryComplementos.DataSet.Eof do
    begin
      Complemento := TJSONObject.Create;
      Complemento.AddPair('codigo', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('CA_CODIGO').AsInteger));
      Complemento.AddPair('nome', QueryComplementos.DataSet.FieldByName('ADI_NOME').AsString);
      Complemento.AddPair('valor', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('ADI_VALOR').AsCurrency));
      Complemento.AddPair('quantidade', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('CA_QUANTIDADE').AsFloat));
      Complementos.AddElement(Complemento);
      QueryComplementos.DataSet.Next;
    end;
    Item.AddPair('complementos', Complementos);
     //Opcoes niveis
      QueryOpcoesNiveis := TDatabase.Query;
      QueryOpcoesNiveis.Clear;
      QueryOpcoesNiveis.Add('SELECT CO_CODIGO, CO_CP, CO_NI, CO_QUANTIDADE, CO_VALOR, CO_NOME, CO_ATIVO, CO_SELECIONADO, CO_OP');
      QueryOpcoesNiveis.Add('FROM CP_OPCOES WHERE CO_CP = :COM_PRO ORDER BY CO_CODIGO');    
      QueryOpcoesNiveis.AddParam('COM_PRO', Query.DataSet.FieldByName('CP_CODIGO').AsInteger);
      QueryOpcoesNiveis.Open;
      Opcoes := TJSONArray.Create;
      QueryOpcoesNiveis.DataSet.First;
      while not QueryOpcoesNiveis.DataSet.Eof do
      begin
        Opcao := TJSONObject.Create;
        Opcao.AddPair('codigo', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_OP').AsInteger));
        Opcao.AddPair('nome', QueryOpcoesNiveis.DataSet.FieldByName('CO_NOME').AsString);
        Opcao.AddPair('valorAdicional', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_VALOR').AsCurrency));
        Opcao.AddPair('ativo', TJSONBool.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_ATIVO').AsString.Contains('S')));
        Opcao.AddPair('ativoStr', QueryOpcoesNiveis.DataSet.FieldByName('CO_ATIVO').AsString);
        Opcao.AddPair('codNivel', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_NI').AsInteger));
        Opcao.AddPair('selecionado', TJSONBool.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_SELECIONADO').AsString.Contains('S')));
        Opcao.AddPair('quantidade', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_QUANTIDADE').AsFloat));
        Opcoes.AddElement(Opcao);
        QueryOpcoesNiveis.DataSet.Next;
      end;
    Item.AddPair('OpcoesNiveis', Opcoes);
    Query.DataSet.Next;
  end;
  Res.Send<TJSONObject>(Item);
end;

class procedure TComandasController.GetPorCodigo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query, QueryComplementos: iQuery;
  Codigo: integer;
  CodigoComanda: integer;
  Comanda: TJSONObject;
  Produtos: TJSONArray;
  Item: TJSONObject;
  Itens: TJSONArray;
  Complemento: TJSONObject;
  Complementos: TJSONArray;
  QueryOpcoesNiveis: iQuery;
  CpOpcoes: TCpOpcoes;
  CpAdicionais: TCpAdicionais;
  Opcoes: TJSONArray;
  Opcao: TJSONObject;
begin
	CpOpcoes := TCpOpcoes.Create(TDatabase.Connection);
  try
    CpOpcoes.CriaTabela;
  finally
    CpOpcoes.DisposeOf;
  end;
  CpAdicionais := TCpAdicionais.Create(TDatabase.Connection);
  try
    CpAdicionais.CriaTabela;
  finally
    CpAdicionais.DisposeOf;
  end;
  if Req.Params.Count = 0 then
    raise Exception.Create('Paramentro "Codigo" não informado!');
  Codigo := Req.Params.Items['codigo'].ToInteger;
  Query  := TDatabase.Query;
  Query.Clear;
  Query.Add('SELECT COM_CODIGO, COM_MESA, COM_DATA_ABERTURA, COM_HORA_ABERTURA, COM_DATA_FECHAMENTO, COM_HORA_FECHAMENTO, COM_DATAC, COM_VALOR, COM_COMANDA FROM COMANDAS');
  Query.Add('WHERE COM_CODIGO = (SELECT MAX(COM_CODIGO) FROM COMANDAS WHERE COM_DATA_FECHAMENTO IS NULL AND COM_MESA = :CODIGO)');
  Query.AddParam('CODIGO', Codigo);
  Query.Open;
  CodigoComanda := Query.DataSet.FieldByName('COM_CODIGO').AsInteger;
  Comanda       := Query.DataSet.ToJSONObject;
  // itens
  Query.Clear;
  Query.Add('SELECT CP_CODIGO, CP_COM, CP_PRO, CP_QUANTIDADE, CP_VALOR, CP_GRA, CP_OBS,');
  Query.Add('CP_ESTADO, PRO_NOME, CP_USU, CP_ID_AGRUPAMENTO ');
  Query.Add('FROM COM_PRO CP JOIN PRODUTOS ON PRO_CODIGO = CP_PRO ');
  Query.Add('WHERE CP_COM = :CODIGO AND CP_ESTADO <> ''E'' ORDER BY CP_CODIGO');
  Query.AddParam('CODIGO', CodigoComanda);
  Query.Open;
  Itens := TJSONArray.Create;
  Query.DataSet.First;
  while not Query.DataSet.Eof do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('cpCodigo', TJSONNumber.Create(Query.DataSet.FieldByName('CP_CODIGO').AsInteger));
    Item.AddPair('cpCom', TJSONNumber.Create(Query.DataSet.FieldByName('CP_COM').AsInteger));
    Item.AddPair('cpPro', TJSONNumber.Create(Query.DataSet.FieldByName('CP_PRO').AsInteger));
    Item.AddPair('cpQuantidade', TJSONNumber.Create(Query.DataSet.FieldByName('CP_QUANTIDADE').AsFloat));
    Item.AddPair('cpValor', TJSONNumber.Create(Query.DataSet.FieldByName('CP_VALOR').AsCurrency));
    Item.AddPair('cpGra', TJSONNumber.Create(Query.DataSet.FieldByName('CP_GRA').AsInteger));
    Item.AddPair('cpObs', Query.DataSet.FieldByName('CP_OBS').AsString);
    Item.AddPair('cpEstado', Query.DataSet.FieldByName('CP_ESTADO').AsString);
    Item.AddPair('nome', Query.DataSet.FieldByName('PRO_NOME').AsString);
    Item.AddPair('gradeProduto', BuscaDadosGrade(Query.DataSet.FieldByName('CP_GRA').AsInteger));
    Item.AddPair('usuario', TJSONNumber.Create(Query.DataSet.FieldByName('CP_USU').AsInteger));
    Item.AddPair('idAgrupamento', Query.DataSet.FieldByName('CP_ID_AGRUPAMENTO').AsString);
    //adicionais
    QueryComplementos := TDatabase.Query;
    QueryComplementos.Clear;
    QueryComplementos.Add('SELECT CA_CODIGO, CA_CP, CA_ADI, CA_QUANTIDADE, ADI_NOME, ADI_VALOR FROM CP_ADICIONAIS JOIN ADICIONAIS ON CA_ADI = ADI_CODIGO WHERE CA_CP = :COM_PRO ORDER BY CA_CODIGO');
    QueryComplementos.AddParam('COM_PRO', Query.DataSet.FieldByName('CP_CODIGO').AsInteger);
    QueryComplementos.Open;
    Complementos := TJSONArray.Create;
    while not QueryComplementos.DataSet.Eof do
    begin
      Complemento := TJSONObject.Create;
      Complemento.AddPair('codigo', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('CA_CODIGO').AsInteger));
      Complemento.AddPair('nome', QueryComplementos.DataSet.FieldByName('ADI_NOME').AsString);
      Complemento.AddPair('valor', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('ADI_VALOR').AsCurrency));
      Complemento.AddPair('quantidade', TJSONNumber.Create(QueryComplementos.DataSet.FieldByName('CA_QUANTIDADE').AsFloat));
      Complementos.AddElement(Complemento);
      QueryComplementos.DataSet.Next;
    end;
    Item.AddPair('complementos', Complementos);
     //Opcoes niveis
      QueryOpcoesNiveis := TDatabase.Query;
      QueryOpcoesNiveis.Clear;
      QueryOpcoesNiveis.Add('SELECT CO_CODIGO, CO_CP, CO_NI, CO_QUANTIDADE, CO_VALOR, CO_NOME, CO_ATIVO, CO_SELECIONADO, CO_OP');
      QueryOpcoesNiveis.Add('FROM CP_OPCOES WHERE CO_CP = :COM_PRO ORDER BY CO_CODIGO');    
      QueryOpcoesNiveis.AddParam('COM_PRO', Query.DataSet.FieldByName('CP_CODIGO').AsInteger);
      QueryOpcoesNiveis.Open;
      Opcoes := TJSONArray.Create;
      QueryOpcoesNiveis.DataSet.First;
      while not QueryOpcoesNiveis.DataSet.Eof do
      begin
        Opcao := TJSONObject.Create;
        Opcao.AddPair('codigo', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_OP').AsInteger));
        Opcao.AddPair('nome', QueryOpcoesNiveis.DataSet.FieldByName('CO_NOME').AsString);
        Opcao.AddPair('valorAdicional', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_VALOR').AsCurrency));
        Opcao.AddPair('ativo', TJSONBool.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_ATIVO').AsString.Contains('S')));
        Opcao.AddPair('ativoStr', QueryOpcoesNiveis.DataSet.FieldByName('CO_ATIVO').AsString);
        Opcao.AddPair('codNivel', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_NI').AsInteger));
        Opcao.AddPair('selecionado', TJSONBool.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_SELECIONADO').AsString.Contains('S')));
        Opcao.AddPair('quantidade', TJSONNumber.Create(QueryOpcoesNiveis.DataSet.FieldByName('CO_QUANTIDADE').AsFloat));
        Opcoes.AddElement(Opcao);
        QueryOpcoesNiveis.DataSet.Next;
      end;
    Item.AddPair('OpcoesNiveis', Opcoes);
    Itens.AddElement(Item);
    Query.DataSet.Next;
  end;
  Comanda.AddPair('itens', Itens);
  Res.Send<TJSONObject>(Comanda);
end;

class procedure TComandasController.Post(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Query: iQuery;
  Comanda: TModelComanda;
  i: integer;
  CodigoComanda: integer;
  Item: TModelItens;
  CodigoComPro: integer;
  Complementos: TArray<TModelComplemento>;
  c: integer;
  TotalComanda: Currency;
  TotalComplementos: Currency;
  Opcoes: TArray<TModelOpcoesNiveis>;
  o: Integer;
  TotalOpcoesNiveis: Currency;
  CpOpcoes: TCpOpcoes;
  CpAdicionais: TCpAdicionais;
begin
	CpOpcoes := TCpOpcoes.Create(TDatabase.Connection);
  try
    CpOpcoes.CriaTabela;
  finally
    CpOpcoes.DisposeOf;
  end;
  CpAdicionais := TCpAdicionais.Create(TDatabase.Connection);
  try
    CpAdicionais.CriaTabela;
  finally
    CpAdicionais.DisposeOf;
  end;
  if Req.Body = '' then
    raise Exception.Create('Comanda não encontrada');
  Comanda := TModelComanda.FromJsonString(Req.Body);
  Query   := TDatabase.Query;
  Query.Clear;
  Query.Add('INSERT INTO COMANDAS (COM_CODIGO, COM_MESA, COM_DATA_ABERTURA, COM_HORA_ABERTURA, COM_VALOR)');
  Query.Add('VALUES (GEN_ID(GEN_COM_CODIGO, 1), :MESA, :DATA_ABERTURA, :HORA_ABERTURA, :VALOR) RETURNING COM_CODIGO');
  Query.AddParam('MESA', Comanda.Mesa);
  Query.AddParam('DATA_ABERTURA', Date);
  Query.AddParam('HORA_ABERTURA', Now);
  Query.AddParam('VALOR', Comanda.Valor);
  Query.Open();
  CodigoComanda := Query.DataSet.FieldByName('COM_CODIGO').AsInteger;
  For i := Low(Comanda.Itens) to High(Comanda.Itens) do
  begin
    Item := Comanda.Itens[i];
    Query.Clear;
    Query.Add('UPDATE OR INSERT INTO COM_PRO (CP_CODIGO, CP_COM, CP_PRO, ');
    Query.Add('CP_QUANTIDADE, CP_VALOR, CP_GRA, CP_OBS, CP_ESTADO, CP_USU, CP_HORA, CP_ID_AGRUPAMENTO)');
    Query.Add('VALUES (GEN_ID(GEN_CP_CODIGO, 1), :COM, :PRO, ');
    Query.Add(':QUANTIDADE, :VALOR, :GRA, :OBS, :ESTADO, :USUARIO, :HORA, :ID_AGRUPAMENTO)');
    Query.Add('MATCHING (CP_CODIGO) RETURNING (CP_CODIGO)');
    Query.AddParam('COM', CodigoComanda);
    Query.AddParam('PRO', Item.Produto);
    Query.AddParam('QUANTIDADE', Item.Quantidade);
    Query.AddParam('VALOR', Item.Valor);
    Query.AddParam('GRA', Item.Grade);
    Query.AddParam('OBS', Item.Obs);
    Query.AddParam('ESTADO', 'A');
    Query.AddParam('USUARIO', Item.usuario);
    Query.AddParam('HORA', Now);
    Query.AddParam('ID_AGRUPAMENTO', Item.IdAgrupamento);
    Query.Open;
    if not Query.DataSet.IsEmpty then
      CodigoComPro := Query.DataSet.FieldByName('CP_CODIGO').AsInteger;
    if CodigoComPro > 0 then
    begin
      Complementos := Comanda.Itens[i].Complementos;
      for c        := Low(Complementos) to High(Complementos) do
      begin
        Query.Clear;
        Query.Add('INSERT INTO CP_ADICIONAIS (CA_CODIGO, CA_CP, CA_ADI, CA_QUANTIDADE)');
        Query.Add('VALUES (GEN_ID(GEN_CP_ADICIONAIS, 1), :CP, :ADI, :QUANTIDADE);');
        Query.AddParam('CP', CodigoComPro);
        Query.AddParam('ADI', Complementos[c].Codigo);
        Query.AddParam('QUANTIDADE', Complementos[c].Quantidade);
        Query.ExecSQL;
      end;
      Opcoes := Comanda.Itens[i].OpcoesNiveis;
      for o        := Low(Opcoes) to High(Opcoes) do
      begin
        Query.Clear;
        Query.Add('INSERT INTO CP_OPCOES (CO_CODIGO, CO_CP, CO_NI, CO_QUANTIDADE, CO_VALOR, CO_NOME, CO_ATIVO, CO_SELECIONADO, CO_OP)');
        Query.Add('VALUES (GEN_ID(GEN_CP_OPCOES, 1), :CP, :NI, :QUANTIDADE, :VALOR, :NOME, :ATIVO, :SELECIONADO, :COD_OPCAO);');
        Query.AddParam('CP', CodigoComPro);
        Query.AddParam('NI', Opcoes[o].codNivel);
        Query.AddParam('QUANTIDADE', Opcoes[o].Quantidade);
        Query.AddParam('VALOR', Opcoes[o].ValorAdicional);
        Query.AddParam('NOME', Opcoes[o].nome);
        Query.AddParam('ATIVO', Opcoes[o].ativoStr);
        Query.AddParam('SELECIONADO', ifthen(Opcoes[o].selecionado, 'S', 'N'));
        Query.AddParam('COD_OPCAO', Opcoes[o].codigo);
        Query.ExecSQL;
      end;
    end;
  end;
  // soma comanda
  Query.Clear;
  Query.Add('SELECT SUM(CP_VALOR) TOTAL');
  Query.Add('FROM COM_PRO JOIN COMANDAS ON CP_COM = COM_CODIGO');
  Query.Add('WHERE COM_CODIGO = :CODIGO AND CP_ESTADO <> ''E''');
  Query.AddParam('CODIGO', CodigoComanda);
  Query.Open();
  TotalComanda := Query.DataSet.FieldByName('TOTAL').AsCurrency;
  // soma adicionais
  Query.Clear;
  Query.Add('SELECT SUM(ADI_VALOR * CA_QUANTIDADE) COMPLEMENTOS');
  Query.Add('FROM COM_PRO JOIN COMANDAS ON CP_COM = COM_CODIGO');
  Query.Add('LEFT JOIN CP_ADICIONAIS ON CA_CP = CP_CODIGO');
  Query.Add('LEFT JOIN ADICIONAIS ON CA_ADI = ADI_CODIGO');
  Query.Add('WHERE COM_CODIGO = :CODIGO AND CP_ESTADO <> ''E''');
  Query.AddParam('CODIGO', CodigoComanda);
  Query.Open();
  TotalComplementos := Query.DataSet.FieldByName('COMPLEMENTOS').AsCurrency;
  // soma opcoes niveis
  Query.Clear;
  Query.Add('SELECT SUM(CO_VALOR * CO_QUANTIDADE) OPCOES');
  Query.Add('FROM COM_PRO JOIN COMANDAS ON CP_COM = COM_CODIGO');
  Query.Add('LEFT JOIN CP_OPCOES ON CO_CP = CP_CODIGO');
  Query.Add('WHERE COM_CODIGO = :CODIGO AND CP_ESTADO <> ''E''');  
  Query.AddParam('CODIGO', CodigoComanda);
  Query.Open();
  TotalOpcoesNiveis := Query.DataSet.FieldByName('OPCOES').AsCurrency;
  // Atualiza comandas
  Query.Clear;
  Query.Add('UPDATE COMANDAS SET COM_VALOR = :VALOR WHERE COM_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', CodigoComanda);
  Query.AddParam('VALOR', TotalComanda + TotalComplementos + TotalOpcoesNiveis);
  Query.ExecSQL;
  // Atualiza o estado da mesa
  Query.Clear;
  Query.Add('UPDATE MESAS SET MES_ESTADO = ''O'' WHERE MES_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', Comanda.Mesa);
  Query.ExecSQL;
  Res.Status(THTTPStatus.Created).Send<TJSONObject>(TJSONObject.Create.AddPair('Comanda', TJSONNumber.Create(CodigoComanda)));
end;

class procedure TComandasController.Registrar;
begin
  THorse.Get('/v1/comandas', Get);
  THorse.Get('/v1/comandas/:codigo', GetPorCodigo);
  THorse.Post('/v1/comandas', Post);
  THorse.Put('/v1/comandas/:codigo/encerrar', EncerrarComanda);
  THorse.Put('/v1/comandas/:codigo/status/:status', AtualizarEstado);
  THorse.Put('/v1/comandas/:codigo', AtualizarComanda);
  THorse.Get('/v1/comandas/item/:codigo', GetItemComPro);
  THorse.Delete('/v1/comandas/:codigo/itens', DeletarItemComanda);
  THorse.Delete('/v1/comandas/:codigo/complementos', DeletarComplementos);
end;

initialization
  Swagger
    // Lista e cria/atualiza comanda
    .Path('comandas')
      .Tag('comandas')
      .GET('Lista Comandas', 'Lista todas as comandas ativas')
        .AddResponse(200, 'Operação bem sucedida').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
      .POST('Cria/Atualiza Comanda', 'Cria uma nova comanda ou atualiza existente')
        .AddParamBody('Dados da Comanda', 'Comanda').Required(True).Schema(TModelComanda).&End
        .AddResponse(201, 'Created')
          .Schema(TModelComanda)
        .&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    // Operacoes por codigo da mesa/comanda
    .Path('comandas/{mesa}')
      .Tag('comandas')
      .GET('Obtem Comanda por codigo da mesa', 'Retorna os dados de uma comanda por codigo da mesa')
        .AddParamPath('mesa', 'Codigo da mesa').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
      .PUT('Atualizar Comanda', 'Atualiza itens/complementos da comanda')
        .AddParamPath('mesa', 'Codigo da mesa').Required(True).Schema(SWAG_INTEGER).&End
        .AddParamBody('Dados da Comanda', 'Comanda').Required(True).Schema(TModelComanda).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    // Encerrar comanda (path com action)
    .Path('comandas/{mesa}/encerrar')
      .Tag('comandas')
      .PUT('Encerrar Comanda', 'Marca a comanda como encerrada e atualiza estado da mesa')
        .AddParamPath('mesa', 'Codigo da mesa').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    .Path('comandas/{codigo}/status/{status}')
      .Tag('comandas')
      .PUT('Status Mesa', 'atualiza estado da mesa')      
        .AddParamPath('codigo', 'Codigo da mesa/comanda').Required(True).Schema(SWAG_INTEGER).&End
        .AddParamPath('status', 'Estado da mesa/comanda').Required(True).Schema(SWAG_STRING).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    // Item e complementos endpoints
    .Path('comandas/item/{codigo}')
      .Tag('comandas')
      .GET('Obtem item com_pro', 'Retorna item da comanda')
        .AddParamPath('codigo', 'Codigo do item').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    .Path('comandas/{codigo}/itens')
      .Tag('comandas')
      .DELETE('Remove item da comanda', 'Remove item por codigo')
        .AddParamPath('codigo', 'Codigo do item').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

    .Path('comandas/{codigo}/complementos')
      .Tag('comandas')
      .DELETE('Remove complementos', 'Remove complementos de um item')
        .AddParamPath('codigo', 'Codigo do com_pro').Required(True).Schema(SWAG_INTEGER).&End
        .AddResponse(200, 'Ok').&End
        .AddResponse(400).&End
        .AddResponse(500).&End
      .&End
    .&End

  .&End

end.
