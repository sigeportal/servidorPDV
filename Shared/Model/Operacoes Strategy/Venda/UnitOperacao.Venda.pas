unit UnitOperacao.Venda;

interface

uses
	UnitOperacoes.Strategy.Interfaces,
	System.Classes,
	System.Math,
	System.Generics.Collections,
	UnitObserver.Model.Interfaces,
	UnitPedFat.Model,
	UnitPF_Parcela.Model,
	UnitVendas.Model,
	UnitVenEst.Model,
	UnitFuncoesComuns,
	UnitFunctions,
	UnitConnection.Model.Interfaces,
	UnitFaturamento.Model,
	UnitTipoPgm.Model,
	UnitRecebimentos.Model,
	UnitCaixa.Model,
	UnitMovimentacoes.Model,
	UnitRecPgm.Model,
	UnitVeAdicionais.Model,
	UnitVeOpcoes.Model;

type
	TOperacaoVenda = class(TInterfacedObject, iOperacoesStrategy)
	private
		FCOD_DAV           : integer;
		FListaPF_Parcela   : TList<TPF_Parcela>;
		FPed_Fat           : TPedFat;
		FTipoFatura        : TTipoFatura;
		FTipoDescontoCartao: TTipoDescontoCartao;
		FPercentualJuros   : Double;
		FVenda             : TVendas;
		ListaItens         : TList<TVenEst>;
		procedure AtualizaMovEstado(CodMov: integer);
	public
		constructor Create;
		destructor Destroy; override;
		class function New: iOperacoesStrategy;
		function SetPF_Parcela(Value: TPF_Parcela): iOperacoesStrategy;
		function SetPed_Fat(Value: TPedFat): iOperacoesStrategy;
		function SetTipoFatura(Value: TTipoFatura): iOperacoesStrategy;
		function SetOperacao(Value: TObject): iOperacoesStrategy;
		function SetItens(Value: TObject): iOperacoesStrategy;
		function SetPercentualJuros(Value: Double): iOperacoesStrategy;
		function SetTipoDescontoCartao(Value: TTipoDescontoCartao): iOperacoesStrategy;
		function InsereOperacao: iOperacoesStrategy;
		function InsereItens: iOperacoesStrategy;
		function InserePedFat: iOperacoesStrategy;
		function InserePFParcela: iOperacoesStrategy;
		function InsereFaturamento: iOperacoesStrategy;
		function CodigoDAV: integer;
	end;

implementation

{ TOperacaoVenda }

uses
	System.SysUtils,
	Vcl.Graphics,
	QRPrntr,
	Vcl.Forms,
	UnitInsereTabela.Model,
	UnitDAV.Model,
	UnitDatabase,
	UnitProdutos.Model,
	UnitHisPro.Model;

procedure TOperacaoVenda.AtualizaMovEstado(CodMov: integer);
var
	Query: iQuery;
begin
	Query := TDatabase.Query;
	try
		Query.Add('UPDATE MOVIMENTACOES SET MOV_ESTADO = ''B'' WHERE MOV_CODIGO = :CODIGO');
		Query.AddParam('CODIGO', CodMov);
		Query.ExecSQL;
	except
		on E: Exception do
		begin
			raise Exception.Create('Erro ao atualizar campo "MOV_ESTADO"!' + sLineBreak + E.Message);
		end;
	end;
end;

function TOperacaoVenda.CodigoDAV: integer;
begin
	Result := FCOD_DAV;
end;

constructor TOperacaoVenda.Create;
begin
	/// ///
	FListaPF_Parcela    := TList<TPF_Parcela>.Create;
	ListaItens          := TList<TVenEst>.Create;
	FTipoDescontoCartao := TTipoDescontoCartao.Despesa;
	FTipoDescontoCartao := TTipoDescontoCartao.Despesa;
end;

destructor TOperacaoVenda.Destroy;
begin
	FListaPF_Parcela.DisposeOf;
	ListaItens.DisposeOf;
  FPed_Fat.DisposeOf;
  FVenda.DisposeOf;
	inherited;
end;

function TOperacaoVenda.InsereFaturamento: iOperacoesStrategy;
var
	Cod_Mov              : integer;
	Cod_Rec              : integer;
	Cod_LDRF             : integer;
	Parcela              : integer;
	i                    : integer;
	Vencimento           : TDateTime;
	ContaCreditar        : integer;
	ValorPago            : Currency;
	SubDespesa           : TSubDespesa;
	CondicaoPgtoAVista   : Boolean;
	EmitirNFCAposOperacao: Boolean;
	Notificacao          : TNotificacao;
	Faturamento          : TFaturamento;
	TipoPgm              : TTipoPgm;
	Recebimento          : TRecebimento;
	Caixa                : TCaixa;
	Movimentacao         : TMovimentacoes;
	RecPgm               : TRecPgm;
begin
	Result := Self;
	try
		// FATURAMENTO DE PEDIDO A PRAZO
		Faturamento           := TFaturamento.Create(TDatabase.Connection);
		Faturamento.Codigo    := FPed_Fat.FAT;
		Faturamento.Cli       := FVenda.Cli;
		Faturamento.Valor     := FVenda.Valor;
		Faturamento.Parcelas  := FPed_Fat.Parcelas;
		Faturamento.Juros     := 0;
		Faturamento.TipoPgm   := integer(FTipoFatura);
		Faturamento.Tipo      := 1;
		Faturamento.Descricao := FVenda.Codigo;
		Faturamento.Data      := FPed_Fat.Data;
		Faturamento.SalvaNoBanco(1);
		Parcela := 1;
		for i   := 0 to Pred(FListaPF_Parcela.Count) do
		begin
			// tipo pgm
			TipoPgm := TTipoPgm.Create(TDatabase.Connection);
			TipoPgm.CriaTabela;
			TipoPgm.BuscaDadosTabela(FListaPF_Parcela[i].TP);
			CondicaoPgtoAVista := (FListaPF_Parcela[i].TP = 0) or (TipoPgm.Condicao.ToUpper = 'V');
			/// insere recebimento
			Cod_Rec     := IncrementaGenerator('GEN_REC');
			Recebimento := TRecebimento.Create(TDatabase.Connection);
			Recebimento.CriaTabela;
			Recebimento.Codigo     := Cod_Rec;
			Recebimento.Valor      := FListaPF_Parcela[i].Valor;
			Recebimento.Vencimento := FListaPF_Parcela[i].Vencimento;
			if CondicaoPgtoAVista then
				Recebimento.Estado := 3
			else
				Recebimento.Estado  := 1;
			Recebimento.Duplicata := FPed_Fat.FAT.ToString + '-' + inttostr(Parcela) + '/' + FPed_Fat.Parcelas.ToString;
			if TipoPgm.Titulo = 'N' then
				Recebimento.Fpg := 1
			else
				Recebimento.Fpg     := 0;
			Recebimento.FAT       := FPed_Fat.FAT;
			Recebimento.Juros     := FListaPF_Parcela[i].Juros;
			Recebimento.Descontos := FListaPF_Parcela[i].Descontos;
			Caixa                 := TCaixa.Create(TDatabase.Connection);
			Caixa.BuscaDadosTabela(GeraCodigo('CAIXA', 'CAI_CODIGO'));
			Recebimento.Cai        := Caixa.Codigo;
			Recebimento.Tipo       := TipoPgm.Descricao;
			Recebimento.Con        := FListaPF_Parcela[i].TP;
			Recebimento.Datar      := FListaPF_Parcela[i].Vencimento;
			Recebimento.Situacao   := 0;
			Recebimento.Descontado := 'N';
			Recebimento.SalvaNoBanco(1);
			/// /
			if CondicaoPgtoAVista then
			begin
				if FTipoDescontoCartao = TTipoDescontoCartao.DescontoRecebimento then
					ValorPago := ifThen(FPercentualJuros > 0, Arredondar(FListaPF_Parcela[i].Valorpg * FPercentualJuros, 2), FListaPF_Parcela[i].Valorpg)
				else
					ValorPago  := FListaPF_Parcela[i].Valorpg;
				Cod_Mov      := IncrementaGenerator('GEN_MOV');
				Movimentacao := TMovimentacoes.Create(TDatabase.Connection);
				Movimentacao.CriaTabela;
				Movimentacao.Codigo    := Cod_Mov;
				Movimentacao.Credito   := ValorPago;
				Movimentacao.Debito    := 0;
				Movimentacao.Descricao := String('VD - ' + FPed_Fat.Cliente).Substring(0, 30);
				Movimentacao.Tipo      := 1;
				Movimentacao.Data      := FPed_Fat.Data;
				Movimentacao.Con       := 0; // caixa
				Movimentacao.Datahora  := Now;
				Movimentacao.Plano     := '1.1';
				Movimentacao.Nome      := 'VENDA';
				Movimentacao.Cai       := Caixa.Codigo;
				Movimentacao.Troco     := 0;
				Movimentacao.PDV       := Caixa.PDV;
				Movimentacao.Executar;
				Movimentacao.DisposeOf;
				// se tem uma conta vinculada ao tipo pgm então faz a transferencia
				ContaCreditar := TipoPgm.Conta;
				if ContaCreditar > 0 then
				begin
					AtualizaMovEstado(Cod_Mov);
					// debita o caixa
					Cod_Mov                := IncrementaGenerator('GEN_MOV');
					Movimentacao           := TMovimentacoes.Create(TDatabase.Connection);
					Movimentacao.Codigo    := Cod_Mov;
					Movimentacao.Credito   := 0;
					Movimentacao.Debito    := ValorPago;
					Movimentacao.Descricao := String('TR - ' + FPed_Fat.Cliente).Substring(0, 30);
					Movimentacao.Tipo      := 5;
					Movimentacao.Data      := FPed_Fat.Data;
					Movimentacao.Con       := 0; // caixa
					Movimentacao.Datahora  := Now;
					Movimentacao.Plano     := '5.4';
					Movimentacao.Nome      := 'TRANSFERENCIA';
					Movimentacao.Cai       := Caixa.Codigo;
					Movimentacao.Troco     := 0;
					Movimentacao.PDV       := Caixa.PDV;
					Movimentacao.Executar;
					Movimentacao.DisposeOf;
					AtualizaMovEstado(Cod_Mov);
					// credita a conta
					Cod_Mov                := IncrementaGenerator('GEN_MOV');
					Movimentacao           := TMovimentacoes.Create(TDatabase.Connection);
					Movimentacao.Codigo    := Cod_Mov;
					Movimentacao.Credito   := ValorPago;
					Movimentacao.Debito    := 0;
					Movimentacao.Descricao := String('VD - ' + FPed_Fat.Cliente).Substring(0, 30);
					Movimentacao.Tipo      := 1;
					Movimentacao.Data      := FPed_Fat.Data;
					Movimentacao.Con       := ContaCreditar;
					Movimentacao.Datahora  := Now;
					Movimentacao.Plano     := '1.1';
					Movimentacao.Nome      := 'VENDA';
					Movimentacao.Cai       := Caixa.Codigo;
					Movimentacao.Troco     := 0;
					Movimentacao.PDV       := Caixa.PDV;
					Movimentacao.Executar;
					Movimentacao.DisposeOf;
				end;
				// altera o vencimento porque foi baixado no mesmo dia
				if CondicaoPgtoAVista then
					Vencimento := Date
				else
					Vencimento := FListaPF_Parcela[i].Vencimento;
				/// //
				RecPgm := TRecPgm.Create(TDatabase.Connection);
				RecPgm.CriaTabela;
				RecPgm.Codigo   := IncrementaGenerator('GEN_RR');
				RecPgm.Datapgm  := Vencimento;
				RecPgm.Dinheiro := ifThen(FPercentualJuros > 0, Arredondar(FListaPF_Parcela[i].Valorpg * FPercentualJuros, 2), FListaPF_Parcela[i].Valorpg);
				RecPgm.Cheque   := 0;
				RecPgm.Rec      := Cod_Rec;
				RecPgm.Hora     := Now;
				RecPgm.Fun      := FPed_Fat.Fun;
				RecPgm.Cai      := Caixa.Codigo;
				RecPgm.Mov      := Cod_Mov;
				RecPgm.SalvaNoBanco(1);
			end
			else
			begin
				RecPgm := TRecPgm.Create(TDatabase.Connection);
				RecPgm.CriaTabela;
				RecPgm.InsereRegistroPrazo(IncrementaGenerator('GEN_RR'), Cod_Rec);
			end;
			Parcela := Parcela + 1;
		end;
	except
		on E: Exception do
		begin
			raise Exception.Create('Erro ao inserir Faturamento Venda!' + sLineBreak + E.Message);
		end;
	end;
end;

function TOperacaoVenda.InsereItens: iOperacoesStrategy;
var
	Cod            : integer;
	Quantidadea    : Double;
	QuantGrade     : Double;
	CodigoVenEst   : integer;
	VenEst         : TVenEst;
	i, c, o        : integer;
	Produto        : TProdutos;
	HisPro         : THisPro;
	Query          : iQuery;
	DavPro         : TDAVItens;
	VenEstAux      : TVenEst;
	ComplementoaAux: TVeAdicionais;
	OpcoesAux      : TVeOpcoes;
  SomaComplementos: Currency;
  SomaOpcoes: Currency;
begin
	Result := Self;
	try
		for i := 0 to Pred(ListaItens.Count) do
		begin
			VenEst := ListaItens[i];
			// salva item
			CodigoVenEst  := IncrementaGenerator('GEN_VE');
			VenEst.Codigo := CodigoVenEst;
			VenEst.Ven    := FVenda.Codigo;
      SomaComplementos := 0;
			// insere os adicionais de complementos
			for c := Low(VenEst.Complementos) to High(VenEst.Complementos) do
			begin
				ComplementoaAux            := VenEst.Complementos[c].Clonar;
				ComplementoaAux.Codigo     := IncrementaGenerator('GEN_VE_ADICIONAIS');
				ComplementoaAux.Ve         := CodigoVenEst;
				ComplementoaAux.Adi        := VenEst.Complementos[c].Adi;
				ComplementoaAux.Quantidade := VenEst.Complementos[c].Quantidade;
				ComplementoaAux.Valor      := VenEst.Complementos[c].Valor;
				ComplementoaAux.SalvaNoBanco(1);
        SomaComplementos := SomaComplementos + (VenEst.Complementos[c].Quantidade * VenEst.Complementos[c].Valor);
			end;
      SomaOpcoes := 0;
			// insere as opcoes
			for o := Low(VenEst.OpcoesNivel) to High(VenEst.OpcoesNivel) do
			begin
				OpcoesAux                := VenEst.OpcoesNivel[o].Clonar;
				OpcoesAux.Codigo         := IncrementaGenerator('GEN_VE_OPCOES');
				OpcoesAux.Ve             := CodigoVenEst;
				OpcoesAux.CodNivel       := VenEst.OpcoesNivel[o].CodNivel;
				OpcoesAux.Quantidade     := VenEst.OpcoesNivel[o].Quantidade;
				OpcoesAux.ValorAdicional := VenEst.OpcoesNivel[o].ValorAdicional;
				OpcoesAux.SalvaNoBanco(1);
        SomaOpcoes := SomaOpcoes + (VenEst.OpcoesNivel[o].Quantidade * VenEst.OpcoesNivel[o].ValorAdicional);
			end;
			// clona o venEst e salva no banco
			VenEstAux := VenEst.Clone;
			try
      	if VenEstAux.Valor = 0 then        
	      	VenEstAux.Valor := SomaComplementos + SomaOpcoes;
				VenEstAux.CriaTabela;
				VenEstAux.SalvaNoBanco(1);
			finally
				VenEstAux.DisposeOf;
			end;
			// quantidade anterior
			Quantidadea := 0;
			Produto     := TProdutos.Create(TDatabase.Connection);
			Produto.BuscaDadosTabela(VenEst.Pro);
			Quantidadea          := Produto.Quantidade;
			Cod                  := IncrementaGenerator('GEN_HP');
			HisPro               := THisPro.Create(TDatabase.Connection);
			HisPro.Codigo        := Cod;
			HisPro.Data          := Date;
			HisPro.Pro           := VenEst.Pro;
			HisPro.Origem        := copy('VD - ' + FVenda.Nome_cliente, 1, 30);
			HisPro.Doc           := FVenda.Codigo.ToString;
			HisPro.Quantidade    := VenEst.Quantidade;
			HisPro.ValorC        := Arredondar(VenEst.ValorC / VenEst.Quantidade, 2);
			HisPro.ValorV        := Arredondar(VenEst.Valor / VenEst.Quantidade, 2);
			HisPro.ValorCM       := Arredondar(VenEst.ValorCM / VenEst.Quantidade, 2);
			HisPro.ValorOp       := Arredondar(VenEst.Valorl / VenEst.Quantidade, 2);
			HisPro.ValorM        := Arredondar(VenEst.Valorf / VenEst.Quantidade, 2);
			HisPro.Tipo          := 'S';
			HisPro.Tipo2         := 1;
			HisPro.QuantAnterior := Quantidadea;
			HisPro.SalvaNoBanco(1);
			/// /
			// DA BAIXA NO ESTOQUE E VERIFICA SE O PRODUTO PODE RECEBER O AJUSTE
			if not Produto.Estoque.Contains('N') then
			begin
				Query := TDatabase.Query;
				Query.Clear;
				Query.Add('UPDATE PRODUTOS SET PRO_QUANTIDADE = COALESCE(PRO_QUANTIDADE, 0) - :QUANTIDADE');
				Query.Add('WHERE PRO_CODIGO = :PRODUTO ');
				Query.AddParam('QUANTIDADE', VenEst.Quantidade);
				Query.AddParam('PRODUTO', VenEst.Pro);
				Query.ExecSQL;
			end;
			// Insere o Registro de DAV_PRO
			DavPro := TDAVItens.Create(TDatabase.Connection);
			DavPro.CriaTabela;
			DavPro.Codigo     := IncrementaGenerator('GEN_DP');
			DavPro.CodDav     := FCOD_DAV;
			DavPro.CodPro     := VenEst.Pro;
			DavPro.Quantidade := VenEst.Quantidade;
			DavPro.Valor      := VenEst.Valor;
			DavPro.Valorr     := VenEst.Valorr;
			DavPro.Valorl     := VenEst.Valorl;
			DavPro.Valorf     := VenEst.Valorf;
			DavPro.Lucro      := VenEst.Lucro;
			DavPro.Aliqicms   := FloatToStr(Produto.Totalizador.Aliq_ICMS);
			DavPro.Nome       := Produto.Nome;
			DavPro.Gtin       := VenEst.Gtin;
			DavPro.Embalagem  := VenEst.Embalagem;
			DavPro.Cancelado  := 'N';
			DavPro.Data       := Date;
			DavPro.Nitem      := i + 1;
			DavPro.Acrescimo  := 0;
			DavPro.Desconto   := 0;
			DavPro.Sit_trib   := Produto.Totalizador.Sit_trib;
			DavPro.SalvaNoBanco(1);
		end;
	except
		on E: Exception do
		begin
			raise Exception.Create('Erro ao inserir Ven Est!' + sLineBreak + E.Message);
		end;
	end;
end;

function TOperacaoVenda.InsereOperacao: iOperacoesStrategy;
var
	porc       : Double;
	InsereVenda: iInsereTabela;
	InsereDAV  : iInsereTabela;
	DAV        : TDAV;
	FVendaAux  : TVendas;
begin
	Result       := Self;
	FPed_Fat.FAT := IncrementaGenerator('GEN_FAT');
	try
		if FVenda.Codigo = 0 then
			FVenda.Codigo    := GeraCodigo('VENDAS', 'VEN_CODIGO');
		FVenda.Datac       := StrToDate('01/01/1900');
		FVenda.DAV         := 2;
		FVenda.Data        := Date;
		FVenda.Hora        := Now;
		FVenda.DEVOLUCAO_P := 'N';
		FVenda.FAT         := FPed_Fat.FAT;
		// clona a venda
		FVendaAux := FVenda.Clone;
		try
			FVendaAux.SalvaNoBanco(1);
		finally
			FVendaAux.DisposeOf;
		end;
		try
			// Insere o Registro de DAV
			FCOD_DAV := IncrementaGenerator('GEN_DAV');
			DAV      := TDAV.Create(TDatabase.Connection);
			DAV.CriaTabela;
			DAV.Codigo      := FCOD_DAV;
			DAV.Data        := Date;
			DAV.Hora        := Now;
			DAV.CodFun      := 1;
			DAV.Valor       := FVenda.Valor;
			DAV.CodCli      := FVenda.Cli;
			DAV.Formas_pgm  := 'DINHEIRO';
			DAV.Validade    := '10 DIAS';
			DAV.Estado      := 2; // ESTADO 1=PENDENTE 2=IMPRESSO
			DAV.Novo        := 0;
			DAV.Funcao      := 'ORCAMENTO';
			DAV.CodVenda    := FVenda.Codigo;
			DAV.NomeCliente := FVenda.Nome_cliente;
			DAV.CPF_CNPJ    := '000.000.000-00';
			DAV.Fatura      := FPed_Fat.FAT;
			DAV.SalvaNoBanco(1);
		except
			on E: Exception do
				raise Exception.Create('Erro ao inserir DAV!' + sLineBreak + E.Message);
		end;
	except
		on E: Exception do
		begin
			raise Exception.Create('Erro ao inserir Venda!' + sLineBreak + E.Message);
		end;
	end;
end;

function TOperacaoVenda.InserePedFat: iOperacoesStrategy;
var
	i          : integer;
	SomaVlrPago: Currency;
	Ped_FatAux : TPedFat;
begin
	Result := Self;
	try
		SomaVlrPago      := 0;
		for i            := 0 to Pred(FListaPF_Parcela.Count) do
			SomaVlrPago    := SomaVlrPago + FListaPF_Parcela[i].Valorpg;
		FPed_Fat.Valorpg := SomaVlrPago;
		FPed_Fat.Cod_Ped := FVenda.Codigo;
		FPed_Fat.Codigo  := IncrementaGenerator('GEN_PF');
		Ped_FatAux       := FPed_Fat.Clone;
		try
			Ped_FatAux.CriaTabela;
			Ped_FatAux.SalvaNoBanco(1);
		finally
			Ped_FatAux.DisposeOf;
		end;
	except
		on E: Exception do
		begin
			raise Exception.Create('Erro ao inserir Ped Fat!' + sLineBreak + E.Message);
		end;
	end;
end;

function TOperacaoVenda.InserePFParcela: iOperacoesStrategy;
var
	NumParcelas : integer;
	Parcela     : integer;
	i           : integer;
	PFParcelaAux: TPF_Parcela;
begin
	Result := Self;
	try
		Parcela := 1;
		for i   := 0 to Pred(FListaPF_Parcela.Count) do
		begin
			PFParcelaAux := FListaPF_Parcela[i].Clone;
			try
				PFParcelaAux.CriaTabela;
				PFParcelaAux.Codigo    := IncrementaGenerator('GEN_PFP');
				PFParcelaAux.PF        := FPed_Fat.Codigo;
				PFParcelaAux.Estado    := 2; // Faturado
				PFParcelaAux.Duplicata := FPed_Fat.FAT.ToString + '-' + inttostr(Parcela) + '/' + FPed_Fat.Parcelas.ToString;
				PFParcelaAux.SalvaNoBanco(1);
			finally
				PFParcelaAux.DisposeOf;
			end;
			Inc(Parcela);
		end;
	except
		on E: Exception do
		begin
			raise Exception.Create('Erro ao inserir PF Parcela!' + sLineBreak + E.Message);
		end;
	end;
end;

class function TOperacaoVenda.New: iOperacoesStrategy;
begin
	Result := Self.Create;
end;

function TOperacaoVenda.SetItens(Value: TObject): iOperacoesStrategy;
begin
	Result := Self;
	ListaItens.Add(TVenEst(Value));
end;

function TOperacaoVenda.SetOperacao(Value: TObject): iOperacoesStrategy;
begin
	Result := Self;
	FVenda := TVendas(Value);
end;

function TOperacaoVenda.SetPed_Fat(Value: TPedFat): iOperacoesStrategy;
begin
	Result   := Self;
	FPed_Fat := Value;
end;

function TOperacaoVenda.SetPercentualJuros(Value: Double): iOperacoesStrategy;
begin
	Result           := Self;
	FPercentualJuros := Value;
end;

function TOperacaoVenda.SetPF_Parcela(Value: TPF_Parcela): iOperacoesStrategy;
begin
	Result := Self;
	FListaPF_Parcela.Add(Value);
end;

function TOperacaoVenda.SetTipoDescontoCartao(Value: TTipoDescontoCartao): iOperacoesStrategy;
begin
	Result              := Self;
	FTipoDescontoCartao := Value;
end;

function TOperacaoVenda.SetTipoFatura(Value: TTipoFatura): iOperacoesStrategy;
begin
	Result      := Self;
	FTipoFatura := Value;
end;

end.
